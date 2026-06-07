// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
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
  State createState() {
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
  List _detectedMarkersNano = [];
  List _detectedMarkersClassic = [];

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
  
  // Для ArUco Nano (правая панель)
  double _lastProcessingTimeNano = 0.0;
  String _lastDetectedIdsNano = '';
  ui.Image? _opencvPreviewImageNano;
  
  // Для классического ArUco (левая панель)
  double _lastProcessingTimeClassic = 0.0;
  String _lastDetectedIdsClassic = '';
  ui.Image? _opencvPreviewImageClassic;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCameraController(cameraController.description);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FloraWand - Dual ArUco Comparison'),
      ),
      body: Column(
        children: [
          // ВЕРХНЯЯ ЧАСТЬ - СЫРАЯ КАМЕРА
          Expanded(
            flex: 2, // Занимает 2/5 экрана
            child: Container(
              margin: const EdgeInsets.all(5),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: Colors.blueGrey,
                    child: const Text(
                      'Raw Camera Feed',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: ColoredBox(
                        color: Colors.black,
                        child: _cameraPreviewWidget(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // НИЖНЯЯ ЧАСТЬ - ДВЕ ОБРАБОТАННЫЕ ПАНЕЛИ
          Expanded(
            flex: 3, // Занимает 3/5 экрана
            child: Row(
              children: [
                // ЛЕВАЯ ПАНЕЛЬ - Классический ArUco
                Expanded(
                  child: _previewContainer(
                    title: 'Classic ArUco',
                    child: _opencvPreviewImageClassic == null
                        ? const Center(child: Text("Processing...", style: TextStyle(color: Colors.white)))
                        : RawImage(
                            image: _opencvPreviewImageClassic,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                          ),
                  ),
                ),
                // ПРАВАЯ ПАНЕЛЬ - ArUco Nano
                Expanded(
                  child: _previewContainer(
                    title: 'ArUco Nano',
                    child: _opencvPreviewImageNano == null
                        ? const Center(child: Text("Processing...", style: TextStyle(color: Colors.white)))
                        : RawImage(
                            image: _opencvPreviewImageNano,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                          ),
                  ),
                ),
              ],
            ),
          ),
          
          _opencvControlWidget(),
          
          // Информация о детекции
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.black87,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      'Classic: ${_lastProcessingTimeClassic.toStringAsFixed(1)} ms',
                      style: const TextStyle(color: Colors.blue, fontSize: 14),
                    ),
                    Text(
                      'IDs: $_lastDetectedIdsClassic',
                      style: const TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Divider(color: Colors.grey, height: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      'Nano: ${_lastProcessingTimeNano.toStringAsFixed(1)} ms',
                      style: const TextStyle(color: Colors.green, fontSize: 14),
                    ),
                    Text(
                      'IDs: $_lastDetectedIdsNano',
                      style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(5.0),
            child: Row(
              children: [
                _cameraTogglesRowWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraPreviewWidget() {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Center(
        child: Text(
          'Tap a camera',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24.0,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    } else {
      return Listener(
        onPointerDown: (_) => _pointers++,
        onPointerUp: (_) => _pointers--,
        child: CameraPreview(
          controller!,
          child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _handleScaleStart,
              onScaleUpdate: _handleScaleUpdate,
              onTapDown: (TapDownDetails details) =>
                  onViewFinderTap(details, constraints),
            );
          }),
        ),
      );
    }
  }

  Widget _previewContainer({required Widget child, required String title}) {
    return Container(
      padding: const EdgeInsets.all(5),
      margin: const EdgeInsets.all(5),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.blueGrey,
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ColoredBox(color: Colors.black, child: child),
            ),
          ),
        ],
      ),
    );
  }

  Widget _opencvControlWidget() {
    return Container();
  }

  Future<ui.Image> _drawMarkersOnImage(
      ui.Image sourceImage, List<dynamic> markers, ui.Size imageSize, Color markerColor) async {
    if (markers.isEmpty) return sourceImage;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawImage(sourceImage, Offset.zero, Paint());

    final paint = Paint()
      ..color = markerColor
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

      final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 20, fontWeight: FontWeight.bold))
        ..pushStyle(ui.TextStyle(color: markerColor, fontSize: 20))
        ..addText('ID: ${marker.id}');
      final paragraph = paragraphBuilder.build();
      paragraph.layout(const ui.ParagraphConstraints(width: 200));
      canvas.drawParagraph(paragraph, Offset(centerX - 30, centerY - 20));
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(sourceImage.width, sourceImage.height);
    return img;
  }

  // ОБРАБОТКА ДЛЯ КЛАССИЧЕСКОГО ArUco (ЛЕВАЯ ПАНЕЛЬ)
  void _processImageClassicAruco(CameraImage image) async {
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
      
      // КЛАССИЧЕСКАЯ ДЕТЕКЦИЯ ArUco ЧЕРЕЗ OPENCV
      final detectorStopwatch = Stopwatch()..start();
      
      // Используем встроенный детектор ArUco из OpenCV
      final dictionary = cv.aruco_Dictionary_get(cv.aruco_DICT_4X4_50);
      final parameters = cv.aruco_DetectorParameters_create();
      final corners = <List<cv.Point>>[];
      final ids = <int>[];
      final rejected = <List<cv.Point>>[];
      
      cv.aruco_detectMarkers(bgr, dictionary, corners, ids, parameters: parameters, rejectedImgPoints: rejected);
      
      detectorStopwatch.stop();
      final detectorTimeMs = detectorStopwatch.elapsedMicroseconds / 1000.0;

      // Преобразуем результаты в формат для отображения
      final detectedMarkers = <dynamic>[];
      for (int i = 0; i < ids.length; i++) {
        detectedMarkers.add({
          'id': ids[i],
          'corners': corners[i].map((p) => Offset(p.x.toDouble(), p.y.toDouble())).toList(),
        });
      }

      if (detectedMarkers.isNotEmpty) {
        _lastDetectedIdsClassic = detectedMarkers.map((m) => m['id'].toString()).join(', ');
        print('✅ Classic ArUco: ${detectorTimeMs.toStringAsFixed(3)} ms | Markers: [$_lastDetectedIdsClassic]');
      } else {
        _lastDetectedIdsClassic = 'none';
      }

      setState(() {
        _detectedMarkersClassic = detectedMarkers;
        _lastProcessingTimeClassic = detectorTimeMs;
      });

      final rgba = await cv.cvtColorAsync(bgr, cv.COLOR_BGR2RGBA);
      ui.Image uiImage = await rgba.toUiImage();
      rgba.dispose();

      if (detectedMarkers.isNotEmpty) {
        final imageSize = ui.Size(bgr.width.toDouble(), bgr.height.toDouble());
        uiImage = await _drawMarkersOnImage(uiImage, detectedMarkers, imageSize, Colors.red);
      }

      setState(() {
        _opencvPreviewImageClassic = uiImage;
      });
      
      dictionary?.release();
      parameters?.release();
    } catch (e) {
      print('Classic ArUco Detection error: $e');
    } finally {
      bgr?.dispose();
      mat.dispose();
    }
  }

  // ОБРАБОТКА ДЛЯ ArUco Nano (ПРАВАЯ ПАНЕЛЬ)
  void _processImageNano(CameraImage image) async {
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
        _lastDetectedIdsNano = markers.map((m) => m.id.toString()).join(', ');
        print('✅ ArucoNano: ${detectorTimeMs.toStringAsFixed(3)} ms | Markers: [$_lastDetectedIdsNano]');
      } else {
        _lastDetectedIdsNano = 'none';
      }

      setState(() {
        _detectedMarkersNano = markers;
        _lastProcessingTimeNano = detectorTimeMs;
      });

      final rgba = await cv.cvtColorAsync(bgr, cv.COLOR_BGR2RGBA);
      ui.Image uiImage = await rgba.toUiImage();
      rgba.dispose();

      if (markers.isNotEmpty) {
        final imageSize = ui.Size(bgr.width.toDouble(), bgr.height.toDouble());
        uiImage = await _drawMarkersOnImage(uiImage, markers, imageSize, Colors.green);
      }

      setState(() {
        _opencvPreviewImageNano = uiImage;
      });
    } catch (e) {
      print('Nano Detection error: $e');
    } finally {
      bgr?.dispose();
      mat.dispose();
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (_pointers == 2) {
      return;
    }
    if (controller == null) {
      return;
    }

    final CameraController cameraController = controller!;

    final double scale = _baseScale * details.scale;
    final double zoom = (scale - 1.0) * (_maxAvailableZoom - _minAvailableZoom) + _minAvailableZoom;

    await cameraController.setZoomLevel(zoom);

    _currentScale = scale;
  }

  Widget _cameraTogglesRowWidget() {
    final cameraController = controller;
    final List<Widget> toggles = [];

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
            child: RadioListTile(
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

  Future onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller!.stopImageStream();
      await controller!.setDescription(cameraDescription);
      await controller!.startImageStream((image) {
        _processImageClassicAruco(image);
        _processImageNano(image);
      });
    } else {
      return _initializeCameraController(cameraDescription);
    }
  }

  Future _initializeCameraController(CameraDescription cameraDescription) async {
    final CameraController cameraController = CameraController(
      cameraDescription,
      kIsWeb ? ResolutionPreset.max : ResolutionPreset.high,
      enableAudio: enableAudio,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    controller = cameraController;

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
      await cameraController.startImageStream((image) {
        _processImageClassicAruco(image);
        _processImageNano(image);
      });
      await Future.wait([
        cameraController.getMaxZoomLevel().then((double value) => _maxAvailableZoom = value),
        cameraController.getMinZoomLevel().then((double value) => _minAvailableZoom = value),
      ]);
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          showInSnackBar('You have denied camera access.');
        case 'CameraAccessDeniedWithoutPrompt':
          showInSnackBar('Please go to Settings app to enable camera access.');
        case 'CameraAccessRestricted':
          showInSnackBar('Camera access is restricted.');
        case 'AudioAccessDenied':
          showInSnackBar('You have denied audio access.');
        case 'AudioAccessDeniedWithoutPrompt':
          showInSnackBar('Please go to Settings app to enable audio access.');
        case 'AudioAccessRestricted':
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

  Future onPausePreviewButtonPressed() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return;
    }

    if (cameraController.value.isPreviewPaused) {
      await cameraController.startImageStream((image) {
        _processImageClassicAruco(image);
        _processImageNano(image);
      });
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

List<CameraDescription> _cameras = [];

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const CameraApp());
}