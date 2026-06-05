import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:opencv_core/opencv.dart' as cv;
import 'dart:ffi' as ffi;
import 'package:flutter/material.dart';
import 'dart:io' show Platform;

final DynamicLibrary nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libaruco_detector.so')
    : DynamicLibrary.process();

typedef CreateDetectorNative = Pointer<Void> Function();
typedef CreateDetectorDart = Pointer<Void> Function();

typedef DestroyDetectorNative = Void Function(Pointer<Void> handle);
typedef DestroyDetectorDart = void Function(Pointer<Void> handle);
typedef DetectMarkersNative = Int32 Function(
    Pointer<Void> handle,
    Pointer<Uint8> data,
    Int32 width,
    Int32 height,
    Pointer<Int32> ids,
    Pointer<Float> corners,
    Int32 maxMarkers,
    );

typedef DetectMarkersDart = int Function(
    Pointer<Void> handle,
    Pointer<Uint8> data,
    int width,
    int height,
    Pointer<Int32> ids,
    Pointer<Float> corners,
    int maxMarkers,
    );

final createDetector = nativeLib
    .lookup<NativeFunction<CreateDetectorNative>>('create_detector')
    .asFunction<CreateDetectorDart>();

final destroyDetector = nativeLib
    .lookup<NativeFunction<DestroyDetectorNative>>('destroy_detector')
    .asFunction<DestroyDetectorDart>();

final detectMarkers = nativeLib
    .lookup<NativeFunction<DetectMarkersNative>>('detect_markers')
    .asFunction<DetectMarkersDart>();

class ArucoMarker {
  final int id;
  final List<ui.Offset> corners;

  ArucoMarker(this.id, this.corners);

  @override
  String toString() => 'Marker(id=$id, corners=$corners)';
}

class ArucoDetector {
  late Pointer<Void> _handle;
  bool _disposed = false;

  ArucoDetector() {
    _handle = createDetector();
    if (_handle == nullptr) {
      throw Exception('Failed to create aruco detector');
    }
  }

  void dispose() {
    if (!_disposed) {
      destroyDetector(_handle);
      _disposed = true;
    }
  }

  List<ArucoMarker> detect(Uint8List imageData, int width, int height, {int maxMarkers = 10}) {
    if (_disposed) {
      throw StateError('Detector already disposed');
    }

    final result = <ArucoMarker>[];

    final idsPtr = calloc<Int32>(maxMarkers);
    final cornersPtr = calloc<Float>(maxMarkers * 8);
    final dataPtr = calloc<Uint8>(imageData.length);
    final nativeData = dataPtr.asTypedList(imageData.length);
    nativeData.setAll(0, imageData);

    try {
      final count = detectMarkers(
        _handle,
        dataPtr,
        width,
        height,
        idsPtr,
        cornersPtr,
        maxMarkers,
      );

      print('C++ detector returned $count markers');

      for (int i = 0; i < count; i++) {
        final id = idsPtr[i];
        final corners = <ui.Offset>[];

        for (int j = 0; j < 4; j++) {
          final x = cornersPtr[i * 8 + j * 2];
          final y = cornersPtr[i * 8 + j * 2 + 1];
          corners.add(ui.Offset(x, y));
        }

        result.add(ArucoMarker(id, corners));
      }
    } catch (e) {
      print('Error detecting markers: $e');
    } finally {
      calloc.free(idsPtr);
      calloc.free(cornersPtr);
      calloc.free(dataPtr);
    }

    return result;
  }
}

extension CvMatUiImageExtension on cv.Mat {
  Future<ui.Image> toUiImage({ui.PixelFormat format = ui.PixelFormat.rgba8888}) async {
    final immutable = await ui.ImmutableBuffer.fromUint8List(data);
    ui.ImageDescriptor desc = ui.ImageDescriptor.raw(
      immutable,
      width: width,
      height: height,
      pixelFormat: format,
    );
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}


Uint8List yuv420ToNV21(CameraImage image) {
  final width = image.width;
  final height = image.height;
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];
  final yBuffer = yPlane.bytes;
  final uBuffer = uPlane.bytes;
  final vBuffer = vPlane.bytes;
  final numPixels = width * height + (width * height ~/ 2);
  final nv21 = Uint8List(numPixels);
  int idY = 0;
  int idUV = width * height;
  final uvWidth = width ~/ 2;
  final uvHeight = height ~/ 2;
  final yRowStride = yPlane.bytesPerRow;
  final yPixelStride = yPlane.bytesPerPixel ?? 1;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 2;

  for (int y = 0; y < height; ++y) {
    final yOffset = y * yRowStride;
    for (int x = 0; x < width; ++x) {
      nv21[idY++] = yBuffer[yOffset + x * yPixelStride];
    }
  }

  for (int y = 0; y < uvHeight; ++y) {
    final uvOffset = y * uvRowStride;
    for (int x = 0; x < uvWidth; ++x) {
      final bufferIndex = uvOffset + (x * uvPixelStride);
      nv21[idUV++] = vBuffer[bufferIndex];
      nv21[idUV++] = uBuffer[bufferIndex];
    }
  }
  return nv21;
}

Uint8List yuv420ToRGBA8888(CameraImage image) {
  final int width = image.width;
  final int height = image.height;
  final int uvRowStride = image.planes[1].bytesPerRow;
  final int uvPixelStride = image.planes[1].bytesPerPixel!;
  final int yRowStride = image.planes[0].bytesPerRow;
  final int yPixelStride = image.planes[0].bytesPerPixel!;
  final yBuffer = image.planes[0].bytes;
  final uBuffer = image.planes[1].bytes;
  final vBuffer = image.planes[2].bytes;
  final rgbaBuffer = Uint8List(width * height * 4);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
      final int index = y * width + x;
      final yValue = yBuffer[y * yRowStride + x * yPixelStride];
      final uValue = uBuffer[uvIndex];
      final vValue = vBuffer[uvIndex];
      final r = (yValue + 1.402 * (vValue - 128)).round();
      final g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round();
      final b = (yValue + 1.772 * (uValue - 128)).round();

      rgbaBuffer[index * 4 + 0] = r.clamp(0, 255);
      rgbaBuffer[index * 4 + 1] = g.clamp(0, 255);
      rgbaBuffer[index * 4 + 2] = b.clamp(0, 255);
      rgbaBuffer[index * 4 + 3] = 255;
    }
  }
  return rgbaBuffer;
}

Uint8List nv21ToRGBA8888(CameraImage image) {
  final int width = image.width;
  final int height = image.height;
  final int frameSize = width * height;
  final rgbaBuffer = Uint8List(frameSize * 4);

  if (image.planes.length < 2) {
    print("ERROR: Expected at least 2 planes, got ${image.planes.length}");
    return rgbaBuffer;
  }

  final yPlane = image.planes[0].bytes;
  final uvPlane = image.planes[1].bytes;
  final yRowStride = image.planes[0].bytesPerRow;
  final yPixelStride = image.planes[0].bytesPerPixel ?? 1;
  final uvRowStride = image.planes[1].bytesPerRow;
  final uvPixelStride = image.planes[1].bytesPerPixel ?? 2;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final int yIndex = (y * yRowStride + x * yPixelStride).toInt();
      final int uvIndex = ((y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride).toInt();

      if (yIndex >= yPlane.length) continue;
      if (uvIndex + 1 >= uvPlane.length) continue;

      final int yValue = yPlane[yIndex];
      final int vValue = uvPlane[uvIndex];
      final int uValue = uvPlane[uvIndex + 1];

      int r = (yValue + 1.402 * (vValue - 128)).toInt();
      int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).toInt();
      int b = (yValue + 1.772 * (uValue - 128)).toInt();

      final int rgbaIndex = (y * width + x) * 4;
      rgbaBuffer[rgbaIndex] = r.clamp(0, 255);
      rgbaBuffer[rgbaIndex + 1] = g.clamp(0, 255);
      rgbaBuffer[rgbaIndex + 2] = b.clamp(0, 255);
      rgbaBuffer[rgbaIndex + 3] = 255;
    }
  }
  return rgbaBuffer;
}

Uint8List bgraToRgbaInPlace(Uint8List bgra) {
  final out = Uint8List(bgra.length);
  for (int i = 0; i < bgra.length; i += 4) {
    out[i] = bgra[i + 2];
    out[i + 1] = bgra[i + 1];
    out[i + 2] = bgra[i];
    out[i + 3] = bgra[i + 3];
  }
  return out;
}