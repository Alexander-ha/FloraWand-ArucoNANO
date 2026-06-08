import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:opencv_core/opencv.dart' as cv;
import 'package:flutter/material.dart';
import 'dart:io' show Platform;

final DynamicLibrary nativeAruco = Platform.isAndroid
    ? DynamicLibrary.open('libaruco_classic.so')
    : DynamicLibrary.process();

final ArucoClassicCreateDetector createDetector = nativeAruco
    .lookup<NativeFunction<ArucoClassicCreateDetectorNative>>('create_detector_dict_4x4_50')
    .asFunction();

final ArucoClassicDestroyDetector destroyDetector = nativeAruco
    .lookup<NativeFunction<ArucoClassicDestroyDetectorNative>>('destroy_detector')
    .asFunction();

final ArucoClassicDetectMarkers detectMarkers = nativeAruco
    .lookup<NativeFunction<ArucoClassicDetectMarkersNative>>('detect_markers')
    .asFunction();

typedef ArucoClassicCreateDetectorNative = Pointer<Void> Function();
typedef ArucoClassicCreateDetector = Pointer<Void> Function();

typedef ArucoClassicDestroyDetectorNative = Void Function(Pointer<Void> handle);
typedef ArucoClassicDestroyDetector = void Function(Pointer<Void> handle);

typedef ArucoClassicDetectMarkersNative = Int32 Function(
    Pointer<Void> handle,
    Pointer<Uint8> data,
    Int32 width,
    Int32 height,
    Pointer<Int32> ids,
    Pointer<Float> corners,
    Int32 maxMarkers,
    Pointer<Float> processingTime
    );

typedef ArucoClassicDetectMarkers = int Function(
    Pointer<Void> handle,
    Pointer<Uint8> data,
    int width,
    int height,
    Pointer<Int32> ids,
    Pointer<Float> corners,
    int maxMarkers,
    Pointer<Float> processingTime
    );

class ArucoClassicDetector {
    Pointer<Void> _handle;

    ArucoClassicDetector() : _handle = createDetector();

    ({List<Map<String, dynamic>> markers, double processingTimeMs}) detect(Uint8List bgrData, int width, int height) {
        if (_handle == nullptr) return (markers: [], processingTimeMs: 0.0);

        final ids = malloc<Int32>(10);
        final corners = malloc<Float>(10 * 8);
        final processingTime = malloc<Float>();

        final Pointer<Uint8> dataPtr = malloc.allocate<Uint8>(bgrData.length);
        dataPtr.asTypedList(bgrData.length).setAll(0, bgrData);

        try {
            final result = detectMarkers(
                _handle,
                dataPtr,
                width,
                height,
                ids,
                corners,
                10,
                processingTime
            );

            final elapsedMs = processingTime.value;

            final markers = <Map<String, dynamic>>[];
            for (int i = 0; i < result; i++) {
                final markerId = ids.elementAt(i).value;
                final markerCorners = <Offset>[];
                for (int j = 0; j < 4; j++) {
                    final x = corners.elementAt(i * 8 + j * 2).value;
                    final y = corners.elementAt(i * 8 + j * 2 + 1).value;
                    markerCorners.add(Offset(x, y));
                }
                markers.add({
                    'id': markerId,
                    'corners': markerCorners,
                });
            }
            return (markers: markers, processingTimeMs: elapsedMs);
        } finally {
            malloc.free(ids);
            malloc.free(corners);
            malloc.free(dataPtr);
            malloc.free(processingTime);
        }
    }

    void dispose() {
        if (_handle != nullptr) {
            destroyDetector(_handle);
            _handle = nullptr;
        }
    }
}