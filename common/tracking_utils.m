#import "tracking_utils.h"

#include <math.h>
#include <string.h>

// TODO: Tuneable
static const float kAppleCVAOneEuroMinCutoff = 1.2f;
static const float kAppleCVAOneEuroBeta = 0.003f;
static const float kAppleCVAOneEuroDerivativeCutoff = 1.0f;

static float blend_float(float previous, float current, float alpha) {
    return previous + ((current - previous) * alpha);
}

static float one_euro_alpha(float cutoff, double dt) {
    if (!(cutoff > 0.0f) || !(dt > 0.0)) {
        return 1.0f;
    }
    const double tau = 1.0 / (2.0 * M_PI * (double)cutoff);
    return (float)(1.0 / (1.0 + (tau / dt)));
}

static float one_euro_filter_scalar(AppleCVAOneEuroScalarFilter *filter,
                                    float value, double dt) {
    if (filter == NULL || !isfinite(value)) {
        return value;
    }
    if (!filter->initialized || !(dt > 0.0)) {
        filter->initialized = true;
        filter->value = value;
        filter->derivative = 0.0f;
        return value;
    }

    const float derivative = (value - filter->value) / (float)dt;
    const float derivative_alpha =
        one_euro_alpha(kAppleCVAOneEuroDerivativeCutoff, dt);
    filter->derivative =
        blend_float(filter->derivative, derivative, derivative_alpha);
    const float cutoff = kAppleCVAOneEuroMinCutoff +
                         (kAppleCVAOneEuroBeta * fabsf(filter->derivative));
    const float value_alpha = one_euro_alpha(cutoff, dt);
    filter->value = blend_float(filter->value, value, value_alpha);
    return filter->value;
}

static void one_euro_filter_array(AppleCVAOneEuroScalarFilter *filters,
                                  float *values, size_t count, double dt) {
    if (filters == NULL || values == NULL) {
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        values[i] = one_euro_filter_scalar(&filters[i], values[i], dt);
    }
}

static double face_one_euro_filter_dt(AppleCVAFaceOneEuroFilter *filter,
                                      double timestamp) {
    double dt = 1.0 / 30.0;
    if (filter->has_timestamp && isfinite(timestamp)) {
        dt = timestamp - filter->previous_timestamp;
    }
    if (!(dt > 0.0) || !isfinite(dt)) {
        dt = 1.0 / 30.0;
    } else if (dt < (1.0 / 240.0)) {
        dt = 1.0 / 240.0;
    } else if (dt > 0.1) {
        dt = 0.1;
    }
    if (isfinite(timestamp)) {
        filter->previous_timestamp = timestamp;
        filter->has_timestamp = true;
    }
    return dt;
}

bool AppleCVATrackedFaceHasDrawableLandmarks(const AppleCVATrackedFace *face) {
    return face != NULL && face->valid && face->landmark_pair_count >= 6;
}

bool AppleCVASelectBestTrackedFace(const AppleCVAFrameResult *result,
                                   AppleCVATrackedFace *out_face) {
    if (result == NULL || out_face == NULL) {
        return false;
    }

    memset(out_face, 0, sizeof(*out_face));
    bool has_face = false;
    for (size_t i = 0; i < result->tracked_faces_written; ++i) {
        const AppleCVATrackedFace *candidate = &result->tracked_faces[i];
        if (!AppleCVATrackedFaceHasDrawableLandmarks(candidate)) {
            continue;
        }
        if (!has_face || candidate->failure_type < out_face->failure_type ||
            (candidate->failure_type == out_face->failure_type &&
             candidate->confidence > out_face->confidence)) {
            *out_face = *candidate;
            has_face = true;
        }
    }
    return has_face;
}

void AppleCVAFaceOneEuroFilterReset(AppleCVAFaceOneEuroFilter *filter) {
    if (filter != NULL) {
        memset(filter, 0, sizeof(*filter));
    }
}

void AppleCVAFaceOneEuroFilterApply(AppleCVAFaceOneEuroFilter *filter,
                                    AppleCVATrackedFace *face,
                                    double timestamp) {
    if (filter == NULL || face == NULL) {
        return;
    }
    if (filter->initialized && filter->face_id[0] != '\0' &&
        face->face_id[0] != '\0' &&
        strcmp(filter->face_id, face->face_id) != 0) {
        AppleCVAFaceOneEuroFilterReset(filter);
    }
    if (!filter->initialized) {
        filter->initialized = true;
        if (face->face_id[0] != '\0') {
            strlcpy(filter->face_id, face->face_id, sizeof(filter->face_id));
        }
    }

    const double dt = face_one_euro_filter_dt(filter, timestamp);
    one_euro_filter_array(filter->rect, face->rect, 4, dt);
    face->angle_roll =
        one_euro_filter_scalar(&filter->angle_roll, face->angle_roll, dt);
    one_euro_filter_array(filter->gaze, face->gaze, 3, dt);
    one_euro_filter_array(filter->raw_gaze, face->raw_gaze, 3, dt);
    one_euro_filter_array(filter->smooth_gaze, face->smooth_gaze, 3, dt);
    one_euro_filter_array(filter->left_eye, face->left_eye, 3, dt);
    one_euro_filter_array(filter->right_eye, face->right_eye, 3, dt);
    face->left_eye_pitch = one_euro_filter_scalar(&filter->left_eye_pitch,
                                                  face->left_eye_pitch, dt);
    face->left_eye_yaw =
        one_euro_filter_scalar(&filter->left_eye_yaw, face->left_eye_yaw, dt);
    face->right_eye_pitch = one_euro_filter_scalar(&filter->right_eye_pitch,
                                                   face->right_eye_pitch, dt);
    face->right_eye_yaw =
        one_euro_filter_scalar(&filter->right_eye_yaw, face->right_eye_yaw, dt);
    face->tongue_out =
        one_euro_filter_scalar(&filter->tongue_out, face->tongue_out, dt);
    one_euro_filter_array(filter->raw_rotation, face->raw_rotation, 9, dt);
    one_euro_filter_array(filter->raw_translation, face->raw_translation, 3,
                          dt);
    one_euro_filter_array(filter->smooth_rotation, face->smooth_rotation, 9,
                          dt);
    one_euro_filter_array(filter->smooth_translation, face->smooth_translation,
                          3, dt);
    one_euro_filter_array(filter->raw_blendshapes, face->raw_blendshapes,
                          face->raw_blendshape_count < APPLECVA_MAX_BLENDSHAPES
                              ? face->raw_blendshape_count
                              : APPLECVA_MAX_BLENDSHAPES,
                          dt);
    one_euro_filter_array(filter->blendshapes, face->blendshapes,
                          face->blendshape_count < APPLECVA_MAX_BLENDSHAPES
                              ? face->blendshape_count
                              : APPLECVA_MAX_BLENDSHAPES,
                          dt);
    one_euro_filter_array(filter->smooth_blendshapes, face->smooth_blendshapes,
                          face->smooth_blendshape_count <
                                  APPLECVA_MAX_BLENDSHAPES
                              ? face->smooth_blendshape_count
                              : APPLECVA_MAX_BLENDSHAPES,
                          dt);
    one_euro_filter_array(filter->landmarks, face->landmarks,
                          face->landmark_float_count <
                                  APPLECVA_MAX_LANDMARK_FLOATS
                              ? face->landmark_float_count
                              : APPLECVA_MAX_LANDMARK_FLOATS,
                          dt);
}
