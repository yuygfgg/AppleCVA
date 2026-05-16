#import "applecva.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreVideo/CoreVideo.h>
#include <ImageIO/ImageIO.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool load_image_as_bgra_pixel_buffer(const char *path,
                                            CVPixelBufferRef *out_buffer,
                                            size_t *out_width,
                                            size_t *out_height) {
    bool ok = false;
    CFURLRef url = NULL;
    CGImageSourceRef source = NULL;
    CGImageRef image = NULL;
    CVPixelBufferRef pixel_buffer = NULL;
    CGColorSpaceRef color_space = NULL;
    CGContextRef context = NULL;

    url = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault, (const UInt8 *)path, (CFIndex)strlen(path), false);
    if (url == NULL) {
        fprintf(stderr, "failed to create URL for %s\n", path);
        goto done;
    }
    source = CGImageSourceCreateWithURL(url, NULL);
    if (source == NULL) {
        fprintf(stderr, "failed to open image source for %s\n", path);
        goto done;
    }
    image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    if (image == NULL) {
        fprintf(stderr, "failed to decode image %s\n", path);
        goto done;
    }

    const size_t width = CGImageGetWidth(image);
    const size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0) {
        fprintf(stderr, "image has invalid size\n");
        goto done;
    }

    CVReturn cv =
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, NULL, &pixel_buffer);
    if (cv != kCVReturnSuccess || pixel_buffer == NULL) {
        fprintf(stderr, "CVPixelBufferCreate failed: %d\n", cv);
        goto done;
    }

    cv = CVPixelBufferLockBaseAddress(pixel_buffer, 0);
    if (cv != kCVReturnSuccess) {
        fprintf(stderr, "CVPixelBufferLockBaseAddress failed: %d\n", cv);
        goto done;
    }

    color_space = CGColorSpaceCreateDeviceRGB();
    if (color_space == NULL) {
        fprintf(stderr, "failed to create RGB color space\n");
        CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
        goto done;
    }

    context = CGBitmapContextCreate(
        CVPixelBufferGetBaseAddress(pixel_buffer), width, height, 8,
        CVPixelBufferGetBytesPerRow(pixel_buffer), color_space,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    if (context == NULL) {
        fprintf(stderr, "failed to create bitmap context\n");
        CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
        goto done;
    }

    CGContextDrawImage(
        context, CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height), image);
    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);

    *out_buffer = pixel_buffer;
    *out_width = width;
    *out_height = height;
    pixel_buffer = NULL;
    ok = true;

done:
    if (context != NULL) {
        CGContextRelease(context);
    }
    if (color_space != NULL) {
        CGColorSpaceRelease(color_space);
    }
    if (pixel_buffer != NULL) {
        CVPixelBufferRelease(pixel_buffer);
    }
    if (image != NULL) {
        CGImageRelease(image);
    }
    if (source != NULL) {
        CFRelease(source);
    }
    if (url != NULL) {
        CFRelease(url);
    }
    return ok;
}

static size_t read_env_size_t(const char *name, size_t fallback_value) {
    const char *value = getenv(name);
    if (value == NULL || *value == '\0') {
        return fallback_value;
    }
    char *end = NULL;
    unsigned long long parsed = strtoull(value, &end, 10);
    if (end == NULL || *end != '\0' || parsed == 0) {
        return fallback_value;
    }
    return (size_t)parsed;
}

static uint32_t read_env_u32(const char *name, uint32_t fallback_value) {
    const char *value = getenv(name);
    if (value == NULL || *value == '\0') {
        return fallback_value;
    }
    char *end = NULL;
    unsigned long parsed = strtoul(value, &end, 10);
    if (end == NULL || *end != '\0') {
        return fallback_value;
    }
    return (uint32_t)parsed;
}

static double read_env_double(const char *name, double fallback_value) {
    const char *value = getenv(name);
    if (value == NULL || *value == '\0') {
        return fallback_value;
    }
    char *end = NULL;
    double parsed = strtod(value, &end);
    if (end == NULL || *end != '\0') {
        return fallback_value;
    }
    return parsed;
}

static bool face_is_better(const AppleCVATrackedFace *candidate,
                           const AppleCVATrackedFace *best) {
    if (!candidate->valid) {
        return false;
    }
    if (!best->valid) {
        return true;
    }
    if (candidate->failure_type != best->failure_type) {
        return candidate->failure_type < best->failure_type;
    }
    return candidate->confidence > best->confidence;
}

static void print_face_summary(size_t frame_index,
                               const AppleCVAFrameResult *result) {
    printf("frame %zu: detected=%zu tracked=%zu", frame_index,
           result->detected_face_count, result->tracked_face_count);
    if (result->tracked_faces_written != 0 && result->tracked_faces[0].valid) {
        const AppleCVATrackedFace *face = &result->tracked_faces[0];
        printf(" confidence=%.6f failure=%d blendshapes=%zu landmarks=%zu "
               "face_id=%s",
               face->confidence, face->failure_type, face->blendshape_count,
               face->landmark_pair_count, face->face_id);
    }
    printf("\n");
}

static void print_face_details(const AppleCVATrackedFace *face) {
    if (face == NULL || !face->valid) {
        return;
    }
    printf("best face:\n");
    printf("  id=%s\n", face->face_id);
    printf("  confidence=%.6f failure=%d\n", face->confidence,
           face->failure_type);
    printf("  rect=(%.6f, %.6f, %.6f, %.6f) roll=%.6f\n", face->rect[0],
           face->rect[1], face->rect[2], face->rect[3], face->angle_roll);
    printf("  raw translation=(%.6f, %.6f, %.6f)\n", face->raw_translation[0],
           face->raw_translation[1], face->raw_translation[2]);
    printf("  smooth translation=(%.6f, %.6f, %.6f)\n",
           face->smooth_translation[0], face->smooth_translation[1],
           face->smooth_translation[2]);
    printf("  gaze=(%.6f, %.6f, %.6f)\n", face->gaze[0], face->gaze[1],
           face->gaze[2]);
    printf("  eye yaw/pitch L=(%.6f, %.6f) R=(%.6f, %.6f)\n",
           face->left_eye_yaw, face->left_eye_pitch, face->right_eye_yaw,
           face->right_eye_pitch);
    printf("  tongue_out=%.6f\n", face->tongue_out);
    printf("  landmark_pairs=%zu\n", face->landmark_pair_count);
}

static void print_semantics_summary(const AppleCVASemantics *semantics) {
    if (semantics == NULL || !semantics->valid) {
        return;
    }
    printf("semantics: max_faces=%u blendshape_names=%zu landmark_names=%zu "
           "mesh_vertices=%zu mesh_texcoords=%zu mesh_quads=%zu\n",
           semantics->maximum_tracked_faces, semantics->blendshape_name_count,
           semantics->landmark_name_count,
           semantics->mesh_vertex_float_count / 3,
           semantics->mesh_texcoord_float_count / 2,
           semantics->mesh_quad_index_count / 4);
}

static void print_named_face_details(const AppleCVATrackedFace *face,
                                     const AppleCVASemantics *semantics) {
    if (face == NULL || !face->valid) {
        return;
    }

    printf("named blendshapes:");
    for (size_t i = 0; i < face->blendshape_count && i < 8; ++i) {
        const char *name = NULL;
        if (semantics != NULL && semantics->valid &&
            i < semantics->blendshape_name_count) {
            name = semantics->blendshape_names[i];
        } else if (i < APPLECVA_MAX_BLENDSHAPES) {
            name = AppleCVABlendshapeNames[i];
        }
        printf(" %s=%.6f",
               (name != NULL && name[0] != '\0') ? name : "blendshape",
               face->blendshapes[i]);
    }
    printf(" %s=%.6f\n", AppleCVATongueOutName, face->tongue_out);

    printf("named landmarks:");
    for (size_t i = 0; i < face->landmark_pair_count && i < 6; ++i) {
        const char *name = NULL;
        if (semantics != NULL && semantics->valid &&
            i < semantics->landmark_name_count) {
            name = semantics->landmark_names[i];
        } else if (i < APPLECVA_MAX_LANDMARKS) {
            name = AppleCVALandmarkNames[i];
        }
        const size_t base = i * 2;
        printf(" %s=(%.3f,%.3f)",
               (name != NULL && name[0] != '\0') ? name : "landmark",
               face->landmarks[base], face->landmarks[base + 1]);
    }
    printf("\n");
}

int main(int argc, const char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <image-path>\n", argv[0]);
        return 2;
    }

    const char *image_path = argv[1];
    const size_t repeat_count = read_env_size_t("APPLECVA_REPEAT_COUNT", 6);
    const double timestamp_step =
        read_env_double("APPLECVA_TIMESTAMP_STEP", 1.0 / 30.0);
    const uint32_t lux_level = read_env_u32("APPLECVA_LUX_LEVEL", 150);
    const float focal_scale =
        (float)read_env_double("APPLECVA_FOCAL_SCALE", 1.0);
    const bool use_feature_options =
        (getenv("APPLECVA_OPTIONS_MODE") != NULL &&
         strcmp(getenv("APPLECVA_OPTIONS_MODE"), "feature") == 0);
    const bool disable_rgb_fallback =
        (getenv("APPLECVA_DISABLE_RGB_FALLBACK") != NULL);
    const bool verbose_output = (getenv("APPLECVA_VERBOSE_OUTPUT") != NULL);
    const bool print_semantics = (getenv("APPLECVA_PRINT_SEMANTICS") != NULL);
    const bool dump_raw_output = (getenv("APPLECVA_DUMP_RAW") != NULL);

    AppleCVAConfig config;
    AppleCVAConfigInit(&config);
    config.use_feature_options = use_feature_options;
    config.enable_rgb_fallback_conversion = !disable_rgb_fallback;
    config.focal_scale = focal_scale;
    config.default_lux_level = lux_level;

    AppleCVATracker *tracker = NULL;
    int32_t status = AppleCVATrackerCreate(&config, &tracker);
    if (status != APPLECVA_OK) {
        fprintf(stderr, "AppleCVATrackerCreate failed: %s (%d)\n",
                AppleCVAStatusString(status), status);
        return 1;
    }

    CVPixelBufferRef pixel_buffer = NULL;
    size_t width = 0;
    size_t height = 0;
    if (!load_image_as_bgra_pixel_buffer(image_path, &pixel_buffer, &width,
                                         &height)) {
        AppleCVATrackerDestroy(tracker);
        return 1;
    }

    AppleCVADetectedFace detected_faces[8];
    size_t detected_face_count = 0;
    status = AppleCVADetectFacesWithVision(pixel_buffer, detected_faces,
                                           sizeof(detected_faces) /
                                               sizeof(detected_faces[0]),
                                           &detected_face_count);
    if (status != APPLECVA_OK) {
        fprintf(stderr, "AppleCVADetectFacesWithVision failed: %s (%d)\n",
                AppleCVAStatusString(status), status);
        CVPixelBufferRelease(pixel_buffer);
        AppleCVATrackerDestroy(tracker);
        return 1;
    }

    if (detected_face_count == 0) {
        fprintf(stderr, "Vision did not find any faces\n");
        CVPixelBufferRelease(pixel_buffer);
        AppleCVATrackerDestroy(tracker);
        return 1;
    }

    AppleCVACameraParameters camera_parameters;
    AppleCVAMakeDefaultCameraParameters(width, height, focal_scale,
                                        &camera_parameters);

    AppleCVATrackedFace tracked_faces[8];
    AppleCVAFrameResult frame_result;
    AppleCVAFrameResultInit(&frame_result, tracked_faces,
                            sizeof(tracked_faces) / sizeof(tracked_faces[0]));

    AppleCVATrackedFace best_face;
    memset(&best_face, 0, sizeof(best_face));
    size_t best_frame_index = 0;

    AppleCVASemantics semantics;
    AppleCVASemanticsInit(&semantics);
    const int32_t semantics_status = AppleCVACopySemantics(&semantics);
    const bool have_semantics =
        (semantics_status == APPLECVA_OK && semantics.valid);

    printf("tracker config: repeat_count=%zu timestamp_step=%.6f lux_level=%u "
           "focal_scale=%.3f use_feature_options=%s rgb_fallback=%s\n",
           repeat_count, timestamp_step, lux_level, focal_scale,
           use_feature_options ? "yes" : "no",
           disable_rgb_fallback ? "disabled" : "enabled");
    printf("image %s => %zux%zu\n", image_path, width, height);
    printf("detected faces: %zu\n", detected_face_count);
    if (have_semantics) {
        print_semantics_summary(&semantics);
    } else if (print_semantics || verbose_output) {
        printf("semantics unavailable: %s (%d)\n",
               AppleCVAStatusString(semantics_status), semantics_status);
    }

    for (size_t frame_index = 0; frame_index < repeat_count; ++frame_index) {
        const double timestamp_seconds = timestamp_step * (double)frame_index;
        status = AppleCVATrackerProcessFrame(
            tracker, pixel_buffer, &camera_parameters, detected_faces,
            detected_face_count, timestamp_seconds, lux_level, &frame_result);
        if (status != APPLECVA_OK) {
            fprintf(
                stderr,
                "AppleCVATrackerProcessFrame failed on frame %zu: %s (%d)\n",
                frame_index, AppleCVAStatusString(status), status);
            CVPixelBufferRelease(pixel_buffer);
            AppleCVATrackerDestroy(tracker);
            return 1;
        }

        print_face_summary(frame_index, &frame_result);
        if (frame_result.tracked_faces_written != 0 &&
            face_is_better(&frame_result.tracked_faces[0], &best_face)) {
            best_face = frame_result.tracked_faces[0];
            best_frame_index = frame_index;
        }
    }

    printf("best frame index: %zu\n", best_frame_index);
    print_face_details(&best_face);

    if (verbose_output) {
        print_named_face_details(&best_face,
                                 have_semantics ? &semantics : NULL);
    }

    if (print_semantics && have_semantics) {
        printf("blendshape names:\n");
        for (size_t i = 0; i < semantics.blendshape_name_count; ++i) {
            printf("  [%zu] %s\n", i, semantics.blendshape_names[i]);
        }
        printf("landmark names:\n");
        for (size_t i = 0; i < semantics.landmark_name_count; ++i) {
            printf("  [%zu] %s\n", i, semantics.landmark_names[i]);
        }
    }

    if (dump_raw_output) {
        CFDictionaryRef raw_output = NULL;
        bool aux_flag = false;
        status = AppleCVATrackerCopyRawDecodedOutput(tracker, &raw_output,
                                                     &aux_flag);
        if (status == APPLECVA_OK && raw_output != NULL) {
            printf("raw decoded output (aux=%s):\n",
                   aux_flag ? "true" : "false");
            CFShow(raw_output);
            CFRelease(raw_output);
        } else {
            fprintf(stderr,
                    "AppleCVATrackerCopyRawDecodedOutput failed: %s (%d)\n",
                    AppleCVAStatusString(status), status);
        }
    }

    CVPixelBufferRelease(pixel_buffer);
    AppleCVATrackerDestroy(tracker);
    return 0;
}
