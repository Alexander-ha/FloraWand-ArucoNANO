#ifndef ARUCO_DETECTOR_H
#define ARUCO_DETECTOR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* ArucoDetectorHandle;//псевдоним

ArucoDetectorHandle create_detector();//КОНСТРУКТОР ДЕТЕКТОРА
void destroy_detector(ArucoDetectorHandle handle);//ДЕСТРУКТОР

int detect_markers(
        ArucoDetectorHandle handle,
        const uint8_t* data,
        int width,
        int height,
        int* ids,
        float* corners,  // массив: [x1,y1, x2,y2, x3,y3, x4,y4 и тд] для каждого маркера
        int max_markers,
        float* processing_time_ms
);//обертка функции, передает в аргументы псевдоним, рзамеры окон, ids, и прочее для аруко

#ifdef __cplusplus
}
#endif

#endif