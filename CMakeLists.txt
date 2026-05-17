cmake_minimum_required(VERSION 3.20)

project(AppleCVAVTSSource LANGUAGES OBJC)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(APPLECVA_FRAMEWORKS
    Foundation
    Vision
    CoreFoundation
    CoreGraphics
    CoreVideo
    CoreMedia
    ImageIO)

set(VTS_SOURCE_FRAMEWORKS
    AppKit
    AVFoundation
    CoreImage
    QuartzCore)

function(target_link_apple_frameworks target visibility)
    foreach(framework IN LISTS ARGN)
        target_link_libraries(${target} ${visibility}
                              "-framework ${framework}")
    endforeach()
endfunction()

add_library(applecva SHARED
    lib/applecva.m)

target_include_directories(applecva
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include)

target_compile_options(applecva
    PRIVATE
        -Wall
        -Wextra
        -fobjc-arc)

target_link_apple_frameworks(applecva PUBLIC ${APPLECVA_FRAMEWORKS})

set_target_properties(applecva
    PROPERTIES
        OUTPUT_NAME applecva
        INSTALL_NAME_DIR "@rpath")

add_executable(vts_source
    common/capture.m
    common/tracking_utils.m
    common/tracking_pipeline.m
    common/overlay_view.m
    apps/vts_source/main.m
    apps/vts_source/app_delegate.m
    apps/vts_source/calibration.m
    apps/vts_source/client.m
    apps/vts_source/parameters.m)

target_include_directories(vts_source
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/common
        ${CMAKE_CURRENT_SOURCE_DIR}/apps/vts_source)

target_compile_options(vts_source
    PRIVATE
        -Wall
        -Wextra
        -fobjc-arc)

target_link_libraries(vts_source PRIVATE applecva)
target_link_apple_frameworks(vts_source
    PRIVATE
        ${APPLECVA_FRAMEWORKS}
        ${VTS_SOURCE_FRAMEWORKS})

target_link_options(vts_source
    PRIVATE
        -sectcreate
        __TEXT
        __info_plist
        ${CMAKE_CURRENT_SOURCE_DIR}/apps/vts_source/VTSSourceInfo.plist)

set_target_properties(vts_source
    PROPERTIES
        BUILD_RPATH "@executable_path")
