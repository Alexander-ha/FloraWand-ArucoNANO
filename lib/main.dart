// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ffi';

import 'package:camera/camera.dart';
import 'package:flora_nano_aruco/input_image.dart';
import 'package:flora_nano_aruco/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:opencv_core/opencv.dart' as cv;

/// Camera example home widget.
class CameraExampleHome extends StatefulWidget {
  /// Default Constructor
  const CameraExampleHome({super.key});

  @override
  State<CameraExampleHome> createState() {
    return _CameraExampleHomeState();
  }
}

/// Returns a suitable camera icon for [direction].
IconData getCameraLensIcon(CameraLensDirection direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
      return Icons.camera;
  }
  // This enum is from a different package, so a new value could be added at
  // any time. The example should keep working if that happens.
  // ignore: dead_code
  return Icons.camera;
}

void _logError(String code, String? message) {
  // ignore: avoid_print
  print('Error: $code${message == null ? '' : '\nError Message: $message'}');
}

class _CameraExampleHomeState extends State<CameraExampleHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? controller;
  bool enableAudio = true;
  late ArucoDetector _arucoDetector;
  List<ArucoMarker> _detectedMarkers = [];

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentScale = 1.0;
  double _baseScale = 1.0;
  int frameSkip = 0;
  int processN = 1;
  double _lastProcessingTimeMs = 0.0;
  String _lastDetectedIds = '';

  ui.Image? _opencvPreviewImage;

  // Counting pointers (number of user fingers on screen)
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arucoDetector = ArucoDetector();
  }

  @override
  void dispose() {
    _arucoDetector.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // #docregion AppLifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCameraController(cameraController.description);
    }
  }
  // #enddocregion AppLifecycle

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera example'),
      ),
      body: Column(
        children: <Widget>[
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(
                      color: controller != null && controller!.value.isRecordingVideo
                          ? Colors.redAccent
                          : Colors.grey,
                      width: 3.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(1.0),
                    child: Center(
                      child: _cameraPreviewWidget(),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _previewContainer(
                    child: _opencvPreviewImage == null
                        ? const Text("waiting...")
                        : RawImage(
                      image: _opencvPreviewImage,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                    )),
              ),
            ],
          ),
          _opencvControlWidget(),
          Padding(
            padding: const EdgeInsets.all(5.0),
            child: Row(
              children: <Widget>[
                _cameraTogglesRowWidget(),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.black54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text(
                  'Processing: ${_lastProcessingTimeMs.toStringAsFixed(1)} ms',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                Text(
                  'IDs: $_lastDetectedIds',
                  style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return Listener(
        onPointerDown: (_) => _pointers++,
        onPointerUp: (_) => _pointers--,
        child: CameraPreview(
          controller!,
          child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _handleScaleStart,
              onScaleUpdate: _handleScaleUpdate,
              onTapDown: (TapDownDetails details) => onViewFinderTap(details, constraints),
            );
          }),
        ),
      );
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale
    if (controller == null || _pointers != 2) {
      return;
    }

    _currentScale = (_baseScale * details.scale).clamp(_minAvailableZoom, _maxAvailableZoom);

    await controller!.setZoomLevel(_currentScale);
  }

  Future<ui.Image> _rgbaBytesToImage(
      Uint8List data,
      int w,
      int h,
      ) async {
    // Always feed RGBA to avoid bgra8888 issues on Chrome.
    final immutable = await ui.ImmutableBuffer.fromUint8List(data);
    ui.ImageDescriptor desc = ui.ImageDescriptor.raw(
      immutable,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<ui.Image> _cvMatToImage(cv.Mat mat, {(int, int)? dstSize}) async {
    final resized = dstSize == null ? mat : await cv.resizeAsync(mat, dstSize);
    final rgba = await cv.cvtColorAsync(resized, cv.COLOR_BGR2RGBA);
    resized.dispose();
    final image = await _rgbaBytesToImage(rgba.data, rgba.width, rgba.height);
    rgba.dispose();
    return image;
  }

  Widget _previewContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(5),
      margin: const EdgeInsets.all(5),
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ColoredBox(color: Colors.black, child: child),
        ),
      ),
    );
  }

  Widget _opencvControlWidget() {
    return Container();
  }
  Future<ui.Image> _drawMarkersOnImage(ui.Image sourceImage, List<ArucoMarker> markers, ui.Size imageSize) async {
    if (markers.isEmpty) return sourceImage;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawImage(sourceImage, Offset.zero, Paint());

    final paint = Paint()
      ..color = const ui.Color.fromARGB(255, 255, 0, 0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final scaleX = imageSize.width / sourceImage.width;
    final scaleY = imageSize.height / sourceImage.height;

    for (final marker in markers) {
      final path = Path();
      for (int i = 0; i < marker.corners.length; i++) {
        final point = Offset(
            marker.corners[i].dx * scaleX,
            marker.corners[i].dy * scaleY
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);

      final centerX = marker.corners.map((c) => c.dx).reduce((a, b) => a + b) / 4 * scaleX;
      final centerY = marker.corners.map((c) => c.dy).reduce((a, b) => a + b) / 4 * scaleY;

      final textStyle = ui.ParagraphStyle(fontSize: 20, fontWeight: FontWeight.bold);
      final paragraphBuilder = ui.ParagraphBuilder(textStyle)
        ..pushStyle(ui.TextStyle(color: const ui.Color.fromARGB(255, 0, 255, 0), fontSize: 20))
        ..addText('ID: ${marker.id}');
      final paragraph = paragraphBuilder.build();
      paragraph.layout(const ui.ParagraphConstraints(width: 200));
      canvas.drawParagraph(paragraph, Offset(centerX - 30, centerY - 20));
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(sourceImage.width, sourceImage.height);
    return img;
  }

  void _processImage(CameraImage image) async {
    frameSkip++;
    if (frameSkip % processN != 0) {
      return;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return;

    final bytes = switch (format) {
      InputImageFormat.yuv_420_888 => yuv420ToRGBA8888(image),
      InputImageFormat.nv21 => nv21ToRGBA8888(image),
      InputImageFormat.bgra8888 => bgraToRgbaInPlace(image.planes.first.bytes),
      _ => throw UnimplementedError(),
    };

    cv.Mat mat = cv.Mat.fromList(
      image.height,
      image.width,
      cv.MatType.CV_8UC4,
      bytes,
    );

    final sensorOrientation = controller?.description.sensorOrientation;
    var rotationCompensation = _orientations[controller?.value.deviceOrientation];
    if (rotationCompensation != null && sensorOrientation != null) {
      if (controller?.description.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }

      switch (rotationCompensation) {
        case 90:
          await cv.rotateAsync(mat, cv.ROTATE_90_CLOCKWISE, dst: mat);
          break;
        case 180:
          await cv.rotateAsync(mat, cv.ROTATE_180, dst: mat);
          break;
        case 270:
          await cv.rotateAsync(mat, cv.ROTATE_90_COUNTERCLOCKWISE, dst: mat);
          break;
      }
    }

    final targetWidth = mat.width ~/ 2;
    final targetHeight = mat.height ~/ 2;
    await cv.resizeAsync(mat, (targetWidth, targetHeight), dst: mat);

    cv.Mat? bgr;
    try {
      bgr = await cv.cvtColorAsync(mat, cv.COLOR_RGBA2BGR);
      final detectorStopwatch = Stopwatch()..start();
      final markers = _arucoDetector.detect(bgr.data, bgr.width, bgr.height);
      detectorStopwatch.stop();
      final detectorTimeMs = detectorStopwatch.elapsedMicroseconds / 1000.0;

      if (markers.isNotEmpty) {
        _lastDetectedIds = markers.map((m) => m.id.toString()).join(', ');

        print('✅ ArucoNano detection: ${detectorTimeMs.toStringAsFixed(3)} ms | Markers: [${_lastDetectedIds}] | Size: ${bgr.width}x${bgr.height}');
      } else {
        _lastDetectedIds = 'none';
      }

      setState(() {
        _detectedMarkers = markers;
        _lastProcessingTimeMs = detectorTimeMs;
      });

      final rgba = await cv.cvtColorAsync(bgr, cv.COLOR_BGR2RGBA);
      ui.Image uiImage = await rgba.toUiImage();
      rgba.dispose();

      if (markers.isNotEmpty) {
        final imageSize = ui.Size(bgr.width.toDouble(), bgr.height.toDouble());
        uiImage = await _drawMarkersOnImage(uiImage, markers, imageSize);
      }

      setState(() {
        _opencvPreviewImage = uiImage;
      });
    } catch (e) {
      print('Detection error: $e');
    } finally {
      bgr?.dispose();
      mat.dispose();
    }
  }
  /// Display a row of toggle to select the camera (or a message if no camera is available).
  Widget _cameraTogglesRowWidget() {
    final cameraController = controller;
    final List<Widget> toggles = <Widget>[];

    void onChanged(CameraDescription? description) {
      if (description == null) {
        return;
      }

      onNewCameraSelected(description);
    }

    if (_cameras.isEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        showInSnackBar('No camera found.');
      });
      return const Text('None');
    } else {
      for (final CameraDescription cameraDescription in _cameras) {
        toggles.add(
          SizedBox(
            width: 150.0,
            child: RadioListTile<CameraDescription>(
              title: Icon(getCameraLensIcon(cameraDescription.lensDirection)),
              groupValue: controller?.description,
              value: cameraDescription,
              onChanged: onChanged,
            ),
          ),
        );
      }
    }
    toggles.add(
      IconButton(
        icon: const Icon(Icons.pause_presentation),
        color: cameraController != null && cameraController.value.isPreviewPaused ? Colors.red : Colors.blue,
        onPressed: cameraController == null ? null : onPausePreviewButtonPressed,
      ),
    );

    return Row(children: toggles);
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (controller == null) {
      return;
    }

    final CameraController cameraController = controller!;

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller!.stopImageStream();
      await controller!.setDescription(cameraDescription);
      await controller!.startImageStream(_processImage);
    } else {
      return _initializeCameraController(cameraDescription);
    }
  }

  Future<void> _initializeCameraController(CameraDescription cameraDescription) async {
    final CameraController cameraController = CameraController(
      cameraDescription,
      kIsWeb ? ResolutionPreset.max : ResolutionPreset.high,
      enableAudio: enableAudio,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    controller = cameraController;

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (mounted) {
        setState(() {});
      }
      if (cameraController.value.hasError) {
        showInSnackBar('Camera error ${cameraController.value.errorDescription}');
      }
    });

    try {
      await cameraController.initialize();
      await cameraController.startImageStream(_processImage);
      await Future.wait(<Future<Object?>>[
        cameraController.getMaxZoomLevel().then((double value) => _maxAvailableZoom = value),
        cameraController.getMinZoomLevel().then((double value) => _minAvailableZoom = value),
      ]);
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          showInSnackBar('You have denied camera access.');
        case 'CameraAccessDeniedWithoutPrompt':
        // iOS only
          showInSnackBar('Please go to Settings app to enable camera access.');
        case 'CameraAccessRestricted':
        // iOS only
          showInSnackBar('Camera access is restricted.');
        case 'AudioAccessDenied':
          showInSnackBar('You have denied audio access.');
        case 'AudioAccessDeniedWithoutPrompt':
        // iOS only
          showInSnackBar('Please go to Settings app to enable audio access.');
        case 'AudioAccessRestricted':
        // iOS only
          showInSnackBar('Audio access is restricted.');
        default:
          _showCameraException(e);
          break;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> onPausePreviewButtonPressed() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return;
    }

    if (cameraController.value.isPreviewPaused) {
      await cameraController.startImageStream(_processImage);
      await cameraController.resumePreview();
    } else {
      await cameraController.stopImageStream();
      await cameraController.pausePreview();
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _showCameraException(CameraException e) {
    _logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }
}

/// CameraApp is the Main Application.
class CameraApp extends StatelessWidget {
  /// Default Constructor
  const CameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: CameraExampleHome(),
    );
  }
}

List<CameraDescription> _cameras = <CameraDescription>[];

Future<void> main() async {
  // Fetch the available cameras before initializing the app.
  try {
    WidgetsFlutterBinding.ensureInitialized();
    _cameras = await availableCameras();
  } on CameraException catch (e) {
    _logError(e.code, e.description);
  }
  runApp(const CameraApp());
}