#include "aruco_classic.h"
#include <opencv2/opencv.hpp>
#include <opencv2/aruco.hpp>
#include <vector>
#include <chrono>

class ArucoDetectorWrapper {
public:
    cv::aruco::Dictionary dictionary;
    cv::aruco::DetectorParameters parameters;
    cv::Ptr<cv::aruco::ArucoDetector> detector;

    ArucoDetectorWrapper(int dictionary_id)
            : dictionary(cv::aruco::getPredefinedDictionary(dictionary_id)),
              parameters()
    {
        detector = cv::makePtr<cv::aruco::ArucoDetector>(dictionary, parameters);
    }
};

extern "C" {

ArucoClassicHandle create_detector_dict_4x4_50(void) {
    return new ArucoDetectorWrapper(cv::aruco::DICT_4X4_250);
}
ArucoClassicHandle create_detector_dict_6x6_250(void) {
    return new ArucoDetectorWrapper(cv::aruco::DICT_6X6_250);
}

ArucoClassicHandle create_detector_dict_aruco_mip_36h12(void) {
    return new ArucoDetectorWrapper(cv::aruco::DICT_ARUCO_MIP_36h12);
}

void destroy_detector(ArucoClassicHandle handle) {
    delete static_cast<ArucoDetectorWrapper*>(handle);
}

int detect_markers(
        ArucoClassicHandle handle,
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
    cv::Mat image(height, width, CV_8UC3, const_cast<uint8_t*>(data));

    if (image.empty()) return -1;

    std::vector<int> marker_ids;
    std::vector<std::vector<cv::Point2f>> marker_corners;

    auto start = std::chrono::high_resolution_clock::now();

    wrapper->detector->detectMarkers(image, marker_corners, marker_ids);

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);

    if (processing_time_ms != nullptr) {
        *processing_time_ms = duration.count() / 1000.0f;
    }

    int found = std::min((int)marker_ids.size(), max_markers);

    for (int i = 0; i < found; i++) {
        ids[i] = marker_ids[i];
        for (int j = 0; j < 4; j++) {
            corners[i * 8 + j * 2] = marker_corners[i][j].x;
            corners[i * 8 + j * 2 + 1] = marker_corners[i][j].y;
        }
    }

    return found;
}

} // extern "C"