#include "aruco_detector.h"
#include "aruco_nano//aruco_nano.h"
#include <opencv2/opencv.hpp>
#include <vector>
#include <memory>

class ArucoDetectorWrapper {//задача создать обертку на основе аруконано под опенсв
public:
    aruco_nano::ArucoDetector detector;//поле детектора и ниже конструктор с словарем аруко

    ArucoDetectorWrapper(): detector(cv::aruco::getPredefinedDictionary(cv::aruco::DICT_ARUCO_MIP_36h12)) {}
};

#ifdef __cplusplus
extern "C" {//подключаем определение на сях классических
#endif

ArucoDetectorHandle create_detector() {//генератор детектора и сокрытие типа для API
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
        int max_markers
) {
    if (!handle || !data) return -1;

    // Отладочный вывод
    //printf("=== C++ detect_markers called ===\n");
    //printf("Width: %d, Height: %d\n", width, height);

    auto* wrapper = static_cast<ArucoDetectorWrapper*>(handle);
    cv::Mat image(height, width, CV_8UC3, const_cast<uint8_t*>(data));

    if (image.empty()) {
        printf("ERROR: Image is empty!\n");
        return -1;
    }

    //printf("Image channels: %d, total size: %d bytes\n", image.channels(), image.total() * image.elemSize());

    std::vector<int> detected_ids;
    std::vector<std::vector<cv::Point2f>> detected_corners;

    //printf("Calling detector.detectMarkers...\n");
    wrapper->detector.detectMarkers(image, detected_corners, detected_ids);

    //printf("Detected %zu markers\n", detected_ids.size());

    // Вывод первых нескольких ID для отладки
    for (size_t i = 0; i < detected_ids.size() && i < 5; i++) {
        printf("Marker %zu: ID=%d\n", i, detected_ids[i]);
    }

    int found = std::min((int)detected_ids.size(), max_markers);

    for (int i = 0; i < found; i++) {
        ids[i] = detected_ids[i];
        const auto& corners_vec = detected_corners[i];
        for (int j = 0; j < 4; j++) {
            corners[i * 8 + j * 2] = corners_vec[j].x;
            corners[i * 8 + j * 2 + 1] = corners_vec[j].y;
        }
    }

    return found;
}

#ifdef __cplusplus
} // extern "C"
#endif
