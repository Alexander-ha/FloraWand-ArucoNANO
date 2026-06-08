cmake_minimum_required(VERSION 3.10)
project(aruco_detector)

set(CMAKE_CXX_STANDARD 17)

if(ANDROID_ABI)
    set(CURRENT_ABI ${ANDROID_ABI})
else()
    set(CURRENT_ABI "arm64-v8a")
endif()

if(NOT OPENCVPATH)
    message(FATAL_ERROR "Please specify OpenCV path: -DOPENCVPATH=/path/to/opencv_core")
endif()

set(OPENCV_BASE "${OPENCVPATH}/android/.cxx/Debug/4n16304y/${CURRENT_ABI}/_deps/libopencv-src")
set(OpenCV_INCLUDE_DIRS "${OPENCV_BASE}/sdk/native/jni/include")
set(OpenCV_LIB_DIR "${OPENCV_BASE}/sdk/native/staticlibs/${CURRENT_ABI}")
set(THIRDPARTY_LIB_DIR "${OPENCV_BASE}/sdk/native/3rdparty/libs/${CURRENT_ABI}")
set(FFMPEG_LIB_DIR "${OPENCV_BASE}/ffmpeg/lib")

message(STATUS "OpenCV include: ${OpenCV_INCLUDE_DIRS}")
message(STATUS "OpenCV lib dir: ${OpenCV_LIB_DIR}")

set(OPTIMIZATION_FLAGS
        -O3
        -ffast-math
        -funroll-loops
        -fomit-frame-pointer
        -flto
        -DNDEBUG
        -DARUCO_NANO_OPTIMIZED
)

if(ANDROID_ABI STREQUAL "arm64-v8a")
    list(APPEND OPTIMIZATION_FLAGS -march=armv8-a+fp+simd -mtune=cortex-a76)
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Release" OR NOT CMAKE_BUILD_TYPE)
    set(CMAKE_CXX_FLAGS_RELEASE "")
    set(CMAKE_C_FLAGS_RELEASE "")

    foreach(flag ${OPTIMIZATION_FLAGS})
        set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} ${flag}")
        set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} ${flag}")
    endforeach()

    message(STATUS "Optimization flags enabled: ${OPTIMIZATION_FLAGS}")
else()
    set(CMAKE_CXX_FLAGS_DEBUG "-O2 -g")
    set(CMAKE_C_FLAGS_DEBUG "-O2 -g")
endif()

if(ANDROID)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fvisibility=default -fvisibility-inlines-hidden")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--gc-sections -Wl,--strip-all")
endif()

message(STATUS "Final CXX flags Release: ${CMAKE_CXX_FLAGS_RELEASE}")
message(STATUS "Final CXX flags Debug: ${CMAKE_CXX_FLAGS_DEBUG}")

add_library(aruco_detector SHARED aruco_detector.cpp)

target_include_directories(aruco_detector PRIVATE
        ${OpenCV_INCLUDE_DIRS}
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

set(OPENCV_MAIN_LIBS
        ${OpenCV_LIB_DIR}/libopencv_calib3d.a
        ${OpenCV_LIB_DIR}/libopencv_core.a
        ${OpenCV_LIB_DIR}/libopencv_imgproc.a
        ${OpenCV_LIB_DIR}/libopencv_objdetect.a
        ${OpenCV_LIB_DIR}/libopencv_features2d.a
        ${OpenCV_LIB_DIR}/libopencv_flann.a
        ${OpenCV_LIB_DIR}/libopencv_photo.a
        ${OpenCV_LIB_DIR}/libopencv_video.a
)

set(THIRDPARTY_LIBS
        ${THIRDPARTY_LIB_DIR}/libade.a
        ${THIRDPARTY_LIB_DIR}/libcpufeatures.a
        ${THIRDPARTY_LIB_DIR}/libIlmImf.a
        ${THIRDPARTY_LIB_DIR}/libkleidicv.a
        ${THIRDPARTY_LIB_DIR}/libkleidicv_hal.a
        ${THIRDPARTY_LIB_DIR}/libkleidicv_thread.a
        ${THIRDPARTY_LIB_DIR}/liblibjpeg-turbo.a
        ${THIRDPARTY_LIB_DIR}/liblibprotobuf.a
        ${THIRDPARTY_LIB_DIR}/libquirc.a
        ${THIRDPARTY_LIB_DIR}/libtegra_hal.a
        ${THIRDPARTY_LIB_DIR}/libzlib.a
)

set(FFMPEG_LIBS
        ${FFMPEG_LIB_DIR}/libavcodec.a
        ${FFMPEG_LIB_DIR}/libavformat.a
        ${FFMPEG_LIB_DIR}/libavutil.a
        ${FFMPEG_LIB_DIR}/libswscale.a
)

target_link_libraries(aruco_detector
        ${OPENCV_MAIN_LIBS}
        ${THIRDPARTY_LIBS}
        ${FFMPEG_LIBS}
        log
        android
        c++_shared
)

if(TARGET aruco_nano)
    target_link_libraries(aruco_detector aruco_nano)
endif()

if(ANDROID)
    set_target_properties(aruco_detector PROPERTIES
            PREFIX "lib"
            SUFFIX ".so"
    )
endif()

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()