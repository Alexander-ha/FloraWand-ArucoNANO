// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flora_nano_aruco/input_image.dart';
import 'package:flora_nano_aruco/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:opencv_core/opencv.dart' as cv;
import 'package:flora_nano_aruco/aruco_bridge.dart';

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

enum DetectorType {
  classic,
  nano,
}

class _CameraExampleHomeState extends State<CameraExampleHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? controller;
  bool enableAudio = true;
  late ArucoDetector _arucoDetector;
  late ArucoClassicDetector _classicDetector;

  DetectorType _activeDetector = DetectorType.classic;

  double _lastProcessingTime = 0.0;
  String _lastDetectedIds = '';
  ui.Image? _processedPreviewImage;
  List _detectedMarkers = [];

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

  int _frameCounter = 0;
  bool _processing = false;
  int _uiUpdateCounter = 0;
  static const int _uiUpdateEveryNFrames = 2;
  int _processEveryNthFrame = 2;

  ui.Image? _lastProcessedImage;
  List _lastMarkers = [];
  double _lastProcTime = 0.0;
  String _lastIds = '';

  // Counting pointers (number of user fingers on screen)
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arucoDetector = ArucoDetector();
    _classicDetector = ArucoClassicDetector();
  }

  @override
  void dispose() {
    _arucoDetector.dispose();
    _classicDetector.dispose();
    _lastProcessedImage?.dispose();
    _processedPreviewImage?.dispose();
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
        title: const Text('FloraWand - ArUco Detector'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: GestureDetector(
                onTap: _toggleDetector,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _activeDetector == DetectorType.classic ? Colors.blue : Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _activeDetector == DetectorType.classic ? 'Classic' : 'Nano',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ОДНА КАМЕРА с обработанным изображением
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(5),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: _activeDetector == DetectorType.classic ? Colors.blue : Colors.green,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _activeDetector == DetectorType.classic ? 'Classic ArUco (C++)' : 'ArUco Nano',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        Icon(
                          _activeDetector == DetectorType.classic ? Icons.code : Icons.speed,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: ColoredBox(
                        color: Colors.black,
                        child: _processedPreviewImage == null
                            ? const Center(
                          child: Text(
                            "Waiting for camera...",
                            style: TextStyle(color: Colors.white),
                          ),
                        )
                            : RawImage(
                          image: _processedPreviewImage,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.low,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Информация о детекции
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.black87,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _activeDetector == DetectorType.classic ? Icons.timer : Icons.speed,
                      color: _activeDetector == DetectorType.classic ? Colors.blue : Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_activeDetector == DetectorType.classic ? "Classic" : "Nano"}: ${_lastProcessingTime.toStringAsFixed(1)} ms',
                      style: TextStyle(
                        color: _activeDetector == DetectorType.classic ? Colors.blue : Colors.green,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 20),
                    const Icon(Icons.qr_code, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'IDs: $_lastDetectedIds',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Tap to switch detector',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(5.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _cameraTogglesRowWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleDetector() {
    setState(() {
      _activeDetector = _activeDetector == DetectorType.classic
          ? DetectorType.nano
          : DetectorType.classic;
      _processedPreviewImage = null;
      _lastDetectedIds = '';
      _lastProcessingTime = 0.0;
    });
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
            },
          ),
        ),
      );
    }
  }

  void _processFrame(CameraImage image) async {
    if (_processing) return;

    _frameCounter++;
    if (_frameCounter % _processEveryNthFrame != 0) return;

    _processing = true;

    try {
      if (_activeDetector == DetectorType.classic) {
        await _processImageClassicOptimized(image);
      } else {
        await _processImageNanoOptimized(image);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _processImageClassicOptimized(CameraImage image) async {
    final mat = await _convertAndResizeImage(image, scale: 1); // Уменьшаем в 3 раза для скорости
    if (mat == null) return;

    cv.Mat? bgr;
    try {
      bgr = await cv.cvtColorAsync(mat, cv.COLOR_RGBA2BGR);

      final stopwatch = Stopwatch()..start();
      final result = _classicDetector.detect(bgr.data, bgr.width, bgr.height);
      stopwatch.stop();

      final markers = result.markers;
      final detectorTimeMs = result.processingTimeMs;

      _lastProcTime = detectorTimeMs;
      if (markers.isNotEmpty) {
        _lastIds = markers.map((m) => m['id'].toString()).join(',');
        if (kDebugMode) {
          print('✅ Classic ArUco: ${detectorTimeMs.toStringAsFixed(3)} ms | Markers: [$_lastIds]');
        }
      } else {
        _lastIds = 'none';
      }
      _lastMarkers = markers;

      // Обновляем UI не чаще чем _uiUpdateEveryNFrames
      _uiUpdateCounter++;
      if (_uiUpdateCounter >= _uiUpdateEveryNFrames) {
        _uiUpdateCounter = 0;
        await _updateUIWithImage(bgr, markers, Colors.blue);
      }

    } catch (e) {
      if (kDebugMode) print('Classic error: $e');
    } finally {
      bgr?.dispose();
      mat.dispose();
    }
  }

  Future<void> _processImageNanoOptimized(CameraImage image) async {
    final mat = await _convertAndResizeImage(image, scale: 1);
    if (mat == null) return;

    cv.Mat? bgr;
    try {
      bgr = await cv.cvtColorAsync(mat, cv.COLOR_RGBA2BGR);

      final result = _arucoDetector.detect(bgr.data, bgr.width, bgr.height);
      final markers = result.markers;
      final detectorTimeMs = result.processingTimeMs;

      // Сохраняем результаты
      _lastProcTime = detectorTimeMs;
      if (markers.isNotEmpty) {
        _lastIds = markers.map((m) => m.id.toString()).join(',');
        if (kDebugMode) {
          print('✅ ArUco Nano: ${detectorTimeMs.toStringAsFixed(3)} ms | Markers: [$_lastIds]');
        }
      } else {
        _lastIds = 'none';
      }

      final markersForDrawing = markers.map((m) => {
        'id': m.id,
        'corners': m.corners,
      }).toList();
      _lastMarkers = markersForDrawing;

      // Обновляем UI
      _uiUpdateCounter++;
      if (_uiUpdateCounter >= _uiUpdateEveryNFrames) {
        _uiUpdateCounter = 0;
        await _updateUIWithImage(bgr, markersForDrawing, Colors.green);
      }

    } catch (e) {
      if (kDebugMode) print('Nano error: $e');
    } finally {
      bgr?.dispose();
      mat.dispose();
    }
  }

  Future<cv.Mat?> _convertAndResizeImage(CameraImage image, {int scale = 2}) async {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

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

    final targetWidth = mat.width ~/ scale;
    final targetHeight = mat.height ~/ scale;
    if (targetWidth > 0 && targetHeight > 0) {
      await cv.resizeAsync(mat, (targetWidth, targetHeight), dst: mat);
    }

    return mat;
  }

  Future<void> _updateUIWithImage(cv.Mat bgr, List markers, Color markerColor) async {
    try {
      final rgba = await cv.cvtColorAsync(bgr, cv.COLOR_BGR2RGBA);
      ui.Image uiImage = await rgba.toUiImage();
      rgba.dispose();

      if (markers.isNotEmpty) {
        final imageSize = ui.Size(bgr.width.toDouble(), bgr.height.toDouble());
        uiImage = await _drawMarkersOnImage(uiImage, markers, imageSize, markerColor);
      }

      if (mounted) {
        setState(() {
          if (_processedPreviewImage != null && _processedPreviewImage != uiImage) {
            _processedPreviewImage?.dispose();
          }
          _processedPreviewImage = uiImage;
          _lastProcessingTime = _lastProcTime;
          _lastDetectedIds = _lastIds;
          _detectedMarkers = _lastMarkers;
        });
      } else {
        uiImage.dispose();
      }

      final old = _lastProcessedImage;
      _lastProcessedImage = uiImage;
      if (old != null && old != uiImage) {
        old.dispose();
      }

    } catch (e) {
      if (kDebugMode) print('UI update error: $e');
    }
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
      final corners = marker['corners'] as List<Offset>;
      for (int i = 0; i < corners.length; i++) {
        final point = Offset(
            corners[i].dx * scaleX,
            corners[i].dy * scaleY
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);

      final centerX = corners.map((c) => c.dx).reduce((a, b) => a + b) / 4 * scaleX;
      final centerY = corners.map((c) => c.dy).reduce((a, b) => a + b) / 4 * scaleY;

      final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 20, fontWeight: FontWeight.bold))
        ..pushStyle(ui.TextStyle(color: markerColor, fontSize: 20))
        ..addText('ID: ${marker['id']}');
      final paragraph = paragraphBuilder.build();
      paragraph.layout(const ui.ParagraphConstraints(width: 200));
      canvas.drawParagraph(paragraph, Offset(centerX - 30, centerY - 20));
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(sourceImage.width, sourceImage.height);
    return img;
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
            width: 120.0,
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

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: toggles);
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
      await controller!.startImageStream(_processFrame);
    } else {
      return _initializeCameraController(cameraDescription);
    }
  }

  Future _initializeCameraController(CameraDescription cameraDescription) async {
    final CameraController cameraController = CameraController(
      cameraDescription,
      kIsWeb ? ResolutionPreset.max : ResolutionPreset.medium, // Используем medium для производительности
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
      await cameraController.startImageStream(_processFrame);
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
      await cameraController.startImageStream(_processFrame);
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