#ifndef ARUCO_CLASSIC_DETECTOR_H
#define ARUCO_CLASSIC_DETECTOR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* ArucoClassicHandle;

ArucoClassicHandle create_detector_default(void);
void destroy_detector(ArucoClassicHandle handle);

ArucoClassicHandle create_detector_dict_6x6_250(void);
ArucoClassicHandle create_detector_dict_aruco_mip_36h12(void);

int detect_markers(
        ArucoClassicHandle handle,
        const uint8_t* data,
        int width,
        int height,
        int* ids,
        float* corners,
        int max_markers,
        float* processing_time_ms
);

#ifdef __cplusplus
}
#endif

#endif