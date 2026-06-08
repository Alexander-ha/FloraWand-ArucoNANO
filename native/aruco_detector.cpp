#include "aruco_detector.h"
#include "aruco_nano/aruco_nano.h"
#include <opencv2/opencv.hpp>
#include <vector>
#include <memory>
#include <chrono>
#include <android/log.h>

class ArucoDetectorWrapper {
public:
    aruco_nano::ArucoDetector detector;
    aruco_nano::DetectorParameters params;

    ArucoDetectorWrapper() {
        params.boxFilterSize = 15;
        params.thres = 3;
        params.minSize = 10;
        params.maxAttemptsPerCandidate = 5;
        params.maxTimesRevisited = 0.05f;
        params.errorCorrectionRate = 0;
        params.maxErroneousBitsInBorderRate = 0.0;
        params.detectInvertedMarker = false;
        auto dict = cv::aruco::getPredefinedDictionary(cv::aruco::DICT_4X4_250);
        params.dicts = {dict};
        detector = aruco_nano::ArucoDetector(params.dicts, params);
    }
};

#ifdef __cplusplus
extern "C" {
#endif

ArucoDetectorHandle create_detector() {
    auto* wrapper = new ArucoDetectorWrapper();
    return static_cast<void*>(wrapper);
}

void destroy_detector(ArucoDetectorHandle handle) {
    delete static_cast<ArucoDetectorWrapper*>(handle);
}

int detect_markers(
        ArucoDetectorHandle handle,
        const uint8_t* data,
        int width,
        int height,
        int* ids,
        float* corners,
        int max_markers,
        float* processing_time_ms
) {
    if (!handle || !data) return -1;

    auto* wrapper = static_cast<ArucoDetectorWrapper*>(handle);

    cv::Mat rgba(height, width, CV_8UC4, const_cast<uint8_t*>(data));
    cv::Mat bgr;
    cv::cvtColor(rgba, bgr, cv::COLOR_RGBA2BGR);

    /*cv::Mat resized;
    if (width > 640) {
        double scale = 640.0 / width;
        cv::resize(bgr, resized, cv::Size(), scale, scale);
    } else {
        resized = bgr;
    }*/
    cv::Mat& resized = bgr;
    __android_log_print(ANDROID_LOG_INFO, "ArucoNano", "Image size: %dx%d, channels: %d", resized.cols, resized.rows, resized.channels());

    std::vector<int> detected_ids;
    std::vector<std::vector<cv::Point2f>> detected_corners;

    auto start = std::chrono::high_resolution_clock::now();

    wrapper->detector.detectMarkers(resized, detected_corners, detected_ids);

    __android_log_print(ANDROID_LOG_INFO, "ArucoNano", "detectMarkers returned %d markers", (int)detected_ids.size());

    for (int i = 0; i < (int)detected_ids.size(); i++) {
        __android_log_print(ANDROID_LOG_INFO, "ArucoNano", "  Marker %d: id=%d", i, detected_ids[i]);
    }
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);

    if (processing_time_ms != nullptr) {
        *processing_time_ms = duration.count() / 1000.0f;
    }

    double scale_x = (double)width;
    double scale_y = (double)height;

    int found = std::min((int)detected_ids.size(), max_markers);

    for (int i = 0; i < found; i++) {
        ids[i] = detected_ids[i];
        const auto& corners_vec = detected_corners[i];
        for (int j = 0; j < 4; j++) {
            corners[i * 8 + j * 2] = corners_vec[j].x * scale_x;
            corners[i * 8 + j * 2 + 1] = corners_vec[j].y * scale_y;
        }
    }

    return found;
}

#ifdef __cplusplus
} // extern "C"
#endif