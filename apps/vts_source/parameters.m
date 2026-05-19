#import "parameters.h"

#include <math.h>
#include <string.h>

static const size_t kVTSMaxCustomParameters = 100;
static const float kVTSSensitivityDefault = 50.0f;

typedef struct {
    size_t blendshapeIndex;
    const char *name;
} VTSAppleCVAIndexedParameterName;

#define VTS_APPLECVA_BLENDSHAPE_LIST(X)                                        \
    X(0, EyeBlinkLeft)                                                         \
    X(1, EyeBlinkRight)                                                        \
    X(2, EyeSquintLeft)                                                        \
    X(3, EyeSquintRight)                                                       \
    X(4, EyeLookDownLeft)                                                      \
    X(5, EyeLookDownRight)                                                     \
    X(6, EyeLookInLeft)                                                        \
    X(7, EyeLookInRight)                                                       \
    X(8, EyeWideLeft)                                                          \
    X(9, EyeWideRight)                                                         \
    X(10, EyeLookOutLeft)                                                      \
    X(11, EyeLookOutRight)                                                     \
    X(12, EyeLookUpLeft)                                                       \
    X(13, EyeLookUpRight)                                                      \
    X(14, BrowDownLeft)                                                        \
    X(15, BrowDownRight)                                                       \
    X(16, BrowInnerUp)                                                         \
    X(17, BrowOuterUpLeft)                                                     \
    X(18, BrowOuterUpRight)                                                    \
    X(19, JawOpen)                                                             \
    X(20, MouthClose)                                                          \
    X(21, JawLeft)                                                             \
    X(22, JawRight)                                                            \
    X(23, JawForward)                                                          \
    X(24, MouthUpperUpLeft)                                                    \
    X(25, MouthUpperUpRight)                                                   \
    X(26, MouthLowerDownLeft)                                                  \
    X(27, MouthLowerDownRight)                                                 \
    X(28, MouthRollUpper)                                                      \
    X(29, MouthRollLower)                                                      \
    X(30, MouthSmileLeft)                                                      \
    X(31, MouthSmileRight)                                                     \
    X(32, MouthDimpleLeft)                                                     \
    X(33, MouthDimpleRight)                                                    \
    X(34, MouthStretchLeft)                                                    \
    X(35, MouthStretchRight)                                                   \
    X(36, MouthFrownLeft)                                                      \
    X(37, MouthFrownRight)                                                     \
    X(38, MouthPressLeft)                                                      \
    X(39, MouthPressRight)                                                     \
    X(40, MouthPucker)                                                         \
    X(41, MouthFunnel)                                                         \
    X(42, MouthLeft)                                                           \
    X(43, MouthRight)                                                          \
    X(44, MouthShrugLower)                                                     \
    X(45, MouthShrugUpper)                                                     \
    X(46, NoseSneerLeft)                                                       \
    X(47, NoseSneerRight)                                                      \
    X(48, CheekPuff)                                                           \
    X(49, CheekSquintLeft)                                                     \
    X(50, CheekSquintRight)

#define VTS_APPLECVA_CUSTOM_NAME(index, name) "ACVA" #name,
static const char *const kCustomBlendshapeNames[APPLECVA_MAX_BLENDSHAPES] = {
    VTS_APPLECVA_BLENDSHAPE_LIST(VTS_APPLECVA_CUSTOM_NAME)};

#define VTS_APPLECVA_ARKIT_ALIAS(index, name) {index, #name},
static const VTSAppleCVAIndexedParameterName kARKitAliasParameters[] = {
    VTS_APPLECVA_BLENDSHAPE_LIST(VTS_APPLECVA_ARKIT_ALIAS)};

#undef VTS_APPLECVA_CUSTOM_NAME
#undef VTS_APPLECVA_ARKIT_ALIAS

#define ARRAY_COUNT(values) (sizeof(values) / sizeof((values)[0]))

#define VTS_APPLECVA_CALIBRATION_FIELDS(X)                                     \
    X(faceAngleXZero, faceAngleX)                                              \
    X(faceAngleYZero, faceAngleY)                                              \
    X(faceAngleZZero, faceAngleZ)                                              \
    X(facePositionXZero, facePositionX)                                        \
    X(facePositionYZero, facePositionY)                                        \
    X(facePositionZNeutral, facePositionZ)                                     \
    X(jawOpenNeutral, jawOpen)                                                 \
    X(eyeOpenLeftNeutral, eyeOpenLeft)                                         \
    X(eyeOpenRightNeutral, eyeOpenRight)                                       \
    X(browLeftYNeutral, browLeftY)                                             \
    X(browRightYNeutral, browRightY)

typedef struct {
    const char *name;
    const char *explanation;
    float minimum;
    float maximum;
    float defaultValue;
} VTSAppleCVAParameterDefinitionSpec;

#define VTS_PARAMETER_DEFINITION(name, explanation, minimum, maximum, value)   \
    {#name, explanation, minimum, maximum, value}

#define VTS_ACVA_DERIVED_PARAMETERS(X)                                         \
    X(ACVATongueOut, "AppleCVA tongue out channel", 0.0f, 1.0f, 0.0f,          \
      tongueOut)                                                               \
    X(ACVAFaceAngleX, "AppleCVA face yaw in degrees", -45.0f, 45.0f, 0.0f,     \
      yaw)                                                                     \
    X(ACVAFaceAngleY, "AppleCVA face pitch in degrees", -45.0f, 45.0f, 0.0f,   \
      pitch)                                                                   \
    X(ACVAFaceAngleZ, "AppleCVA face roll in degrees", -45.0f, 45.0f, 0.0f,    \
      roll)                                                                    \
    X(ACVAFacePositionX, "AppleCVA calibrated face X position", -10.0f, 10.0f, \
      0.0f, facePositionX)                                                     \
    X(ACVAFacePositionY, "AppleCVA calibrated face Y position", -10.0f, 10.0f, \
      0.0f, facePositionY)                                                     \
    X(ACVAFacePositionZ, "AppleCVA calibrated face Z position", -10.0f, 10.0f, \
      0.0f, facePositionZ)                                                     \
    X(ACVAEyeLeftX, "AppleCVA left eye yaw in degrees", -45.0f, 45.0f, 0.0f,   \
      acvaEyeLeftX)                                                            \
    X(ACVAEyeLeftY, "AppleCVA left eye pitch in degrees", -45.0f, 45.0f, 0.0f, \
      acvaEyeLeftY)                                                            \
    X(ACVAEyeRightX, "AppleCVA right eye yaw in degrees", -45.0f, 45.0f, 0.0f, \
      acvaEyeRightX)                                                           \
    X(ACVAEyeRightY, "AppleCVA right eye pitch in degrees", -45.0f, 45.0f,     \
      0.0f, acvaEyeRightY)                                                     \
    X(ACVAEyeOpenLeft, "AppleCVA landmark-derived left eye open", 0.0f, 1.0f,  \
      1.0f, eyeOpenLeft)                                                       \
    X(ACVAEyeOpenRight, "AppleCVA landmark-derived right eye open", 0.0f,      \
      1.0f, 1.0f, eyeOpenRight)                                                \
    X(ACVAMouthSmile, "AppleCVA mouth smile", 0.0f, 1.0f, 0.0f, mouthSmile)    \
    X(ACVAMouthX, "AppleCVA mouth X offset", -1.0f, 1.0f, 0.0f, mouthX)        \
    X(ACVABrowLeftY, "AppleCVA left brow height", 0.0f, 1.0f, 0.5f, browLeftY) \
    X(ACVABrowRightY, "AppleCVA right brow height", 0.0f, 1.0f, 0.5f,          \
      browRightY)

#define VTS_SPECIAL_PARAMETERS(X)                                              \
    X(EyeSmileLeft, "AppleCVA derived left eye smile", 0.0f, 1.0f, 0.0f,       \
      eyeSmileLeft)                                                            \
    X(EyeSmileRight, "AppleCVA derived right eye smile", 0.0f, 1.0f, 0.0f,     \
      eyeSmileRight)                                                           \
    X(BlushWhenSmiling, "AppleCVA smile-driven blush amount", 0.0f, 1.0f,      \
      0.0f, blushWhenSmiling)

#define VTS_DEFINITION_FROM_PARAMETER(name, explanation, min, max, def, value) \
    VTS_PARAMETER_DEFINITION(name, explanation, min, max, def),

static const VTSAppleCVAParameterDefinitionSpec
    kACVADerivedParameterDefinitions[] = {
        VTS_ACVA_DERIVED_PARAMETERS(VTS_DEFINITION_FROM_PARAMETER)};

// Currently not default parameters, but a lot of models use them.
static const VTSAppleCVAParameterDefinitionSpec
    kSpecialVTSParameterDefinitions[] = {
        VTS_SPECIAL_PARAMETERS(VTS_DEFINITION_FROM_PARAMETER)};

#undef VTS_DEFINITION_FROM_PARAMETER
#undef VTS_PARAMETER_DEFINITION

static BOOL parameter_name_is_default(NSString *name,
                                      NSSet<NSString *> *availableDefaults) {
    return name != nil && [availableDefaults containsObject:name];
}

static size_t
arkit_alias_custom_parameter_count(BOOL includeARKitAliases,
                                   NSSet<NSString *> *availableDefaults) {
    if (!includeARKitAliases) {
        return 0;
    }
    size_t count = 0;
    for (size_t i = 0; i < ARRAY_COUNT(kARKitAliasParameters); ++i) {
        NSString *name =
            [NSString stringWithUTF8String:kARKitAliasParameters[i].name];
        if (!parameter_name_is_default(name, availableDefaults)) {
            ++count;
        }
    }
    return count;
}

static size_t
acva_blendshape_parameter_count(BOOL includeARKitAliases,
                                BOOL includeACVABlendshapeParameters,
                                NSSet<NSString *> *availableDefaults) {
    if (!includeACVABlendshapeParameters) {
        return 0;
    }
    const size_t derivedACVAParameterCount =
        ARRAY_COUNT(kACVADerivedParameterDefinitions);
    size_t specialCustomCount = 0;
    for (size_t i = 0; i < ARRAY_COUNT(kSpecialVTSParameterDefinitions); ++i) {
        NSString *name = [NSString
            stringWithUTF8String:kSpecialVTSParameterDefinitions[i].name];
        if (!parameter_name_is_default(name, availableDefaults)) {
            ++specialCustomCount;
        }
    }
    const size_t aliasCustomCount = arkit_alias_custom_parameter_count(
        includeARKitAliases, availableDefaults);
    const size_t reserved =
        derivedACVAParameterCount + specialCustomCount + aliasCustomCount;
    if (reserved >= kVTSMaxCustomParameters) {
        return 0;
    }
    const size_t available = kVTSMaxCustomParameters - reserved;
    return APPLECVA_MAX_BLENDSHAPES < available ? APPLECVA_MAX_BLENDSHAPES
                                                : available;
}

static void log_dropped_acva_blendshape_parameters(size_t includedCount) {
    if (includedCount >= APPLECVA_MAX_BLENDSHAPES) {
        return;
    }

    NSMutableArray<NSString *> *dropped = [NSMutableArray array];
    for (size_t i = includedCount; i < APPLECVA_MAX_BLENDSHAPES; ++i) {
        [dropped addObject:[NSString
                               stringWithUTF8String:kCustomBlendshapeNames[i]]];
    }
    NSLog(@"WARNING: VTS custom parameter slots exhausted; skipped %lu raw "
          @"ACVA blendshape parameters: %@",
          (unsigned long)dropped.count,
          [dropped componentsJoinedByString:@", "]);
}

typedef struct {
    float x;
    float y;
} AppleCVALandmarkPoint;

#define VTS_APPLECVA_BLENDSHAPE_ENUM(index, name)                              \
    VTSAppleCVABlendshape##name = index,
typedef enum {
    VTS_APPLECVA_BLENDSHAPE_LIST(VTS_APPLECVA_BLENDSHAPE_ENUM)
} VTSAppleCVABlendshapeIndex;
#undef VTS_APPLECVA_BLENDSHAPE_ENUM

typedef enum {
    VTSAppleCVALandmarkRightEyeOuterCorner = 0,
    VTSAppleCVALandmarkRightEyeInnerCorner = 1,
    VTSAppleCVALandmarkRightEyeLowerOuter = 2,
    VTSAppleCVALandmarkRightEyeLowerInner = 3,
    VTSAppleCVALandmarkRightEyeUpperOuter = 4,
    VTSAppleCVALandmarkRightEyeUpperInner = 5,
    VTSAppleCVALandmarkLeftEyeOuterCorner = 7,
    VTSAppleCVALandmarkLeftEyeInnerCorner = 8,
    VTSAppleCVALandmarkLeftEyeLowerOuter = 9,
    VTSAppleCVALandmarkLeftEyeLowerInner = 10,
    VTSAppleCVALandmarkLeftEyeUpperOuter = 11,
    VTSAppleCVALandmarkLeftEyeUpperInner = 12,
    VTSAppleCVALandmarkNoseRidgeTip = 43,
    VTSAppleCVALandmarkChinCenter = 59,
} VTSAppleCVALandmarkIndex;

typedef struct {
    size_t blink, squint, wide, browDown, browOuterUp;
    size_t mouthSmile, mouthFrown, cheekSquint;
} VTSAppleCVASideBlendshapeIndices;

#define VTS_SIDE_BLENDSHAPES(side)                                             \
    {VTSAppleCVABlendshapeEyeBlink##side,                                      \
     VTSAppleCVABlendshapeEyeSquint##side,                                     \
     VTSAppleCVABlendshapeEyeWide##side,                                       \
     VTSAppleCVABlendshapeBrowDown##side,                                      \
     VTSAppleCVABlendshapeBrowOuterUp##side,                                   \
     VTSAppleCVABlendshapeMouthSmile##side,                                    \
     VTSAppleCVABlendshapeMouthFrown##side,                                    \
     VTSAppleCVABlendshapeCheekSquint##side}

static const VTSAppleCVASideBlendshapeIndices kSideBlendshapes[] = {
    VTS_SIDE_BLENDSHAPES(Right),
    VTS_SIDE_BLENDSHAPES(Left),
};
#undef VTS_SIDE_BLENDSHAPES

typedef struct {
    size_t outer, inner, lowerOuter, lowerInner, upperOuter, upperInner;
} VTSAppleCVAEyeLandmarkIndices;

#define VTS_EYE_LANDMARKS(side)                                                \
    {VTSAppleCVALandmark##side##EyeOuterCorner,                                \
     VTSAppleCVALandmark##side##EyeInnerCorner,                                \
     VTSAppleCVALandmark##side##EyeLowerOuter,                                 \
     VTSAppleCVALandmark##side##EyeLowerInner,                                 \
     VTSAppleCVALandmark##side##EyeUpperOuter,                                 \
     VTSAppleCVALandmark##side##EyeUpperInner}

static const VTSAppleCVAEyeLandmarkIndices kEyeLandmarks[] = {
    VTS_EYE_LANDMARKS(Right),
    VTS_EYE_LANDMARKS(Left),
};
#undef VTS_EYE_LANDMARKS

static const VTSAppleCVASideBlendshapeIndices *side_blendshapes(BOOL leftSide) {
    return &kSideBlendshapes[leftSide ? 1 : 0];
}

static const VTSAppleCVAEyeLandmarkIndices *eye_landmarks(BOOL leftEye) {
    return &kEyeLandmarks[leftEye ? 1 : 0];
}

static float clampf(float value, float minimum, float maximum) {
    if (!isfinite(value)) {
        return 0.0f;
    }
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}

static float clamp01(float value) { return clampf(value, 0.0f, 1.0f); }

static float clamp_sensitivity(float value) {
    if (!isfinite(value)) {
        return kVTSSensitivityDefault;
    }
    return clampf(value, 0.0f, 100.0f);
}

static float sensitivity_gain(float sensitivity) {
    return clamp_sensitivity(sensitivity) / kVTSSensitivityDefault;
}

VTSAppleCVASensitivityParameters VTSAppleCVASensitivityParametersDefault(void) {
    VTSAppleCVASensitivityParameters parameters = {
        kVTSSensitivityDefault, kVTSSensitivityDefault, kVTSSensitivityDefault,
        kVTSSensitivityDefault, kVTSSensitivityDefault,
    };
    return parameters;
}

VTSAppleCVASensitivityParameters VTSAppleCVASensitivityParametersSanitize(
    VTSAppleCVASensitivityParameters parameters) {
    parameters.blink = clamp_sensitivity(parameters.blink);
    parameters.eyeOpen = clamp_sensitivity(parameters.eyeOpen);
    parameters.mouthOpen = clamp_sensitivity(parameters.mouthOpen);
    parameters.mouthSmile = clamp_sensitivity(parameters.mouthSmile);
    parameters.brow = clamp_sensitivity(parameters.brow);
    return parameters;
}

static float apply_zero_based_sensitivity(float value, float sensitivity) {
    return clamp01(value * sensitivity_gain(sensitivity));
}

static float apply_centered_sensitivity(float value, float center,
                                        float sensitivity, float minimum,
                                        float maximum) {
    return clampf(center + ((value - center) * sensitivity_gain(sensitivity)),
                  minimum, maximum);
}

static float remap_clamped(float value, float inputMinimum, float inputMaximum,
                           float outputMinimum, float outputMaximum) {
    if (!isfinite(value) || inputMaximum == inputMinimum) {
        return outputMinimum;
    }
    const float t =
        clamp01((value - inputMinimum) / (inputMaximum - inputMinimum));
    return outputMinimum + ((outputMaximum - outputMinimum) * t);
}

static NSNumber *json_float(float value) {
    if (!isfinite(value)) {
        value = 0.0f;
    }
    return @(value);
}

static NSDictionary *parameter_definition(NSString *name, NSString *explanation,
                                          float minimum, float maximum,
                                          float defaultValue) {
    return @{
        @"parameterName" : name,
        @"explanation" : explanation,
        @"min" : @(minimum),
        @"max" : @(maximum),
        @"defaultValue" : @(defaultValue),
    };
}

static void
add_parameter_definitions(NSMutableArray *definitions,
                          const VTSAppleCVAParameterDefinitionSpec *specs,
                          size_t count, NSSet<NSString *> *availableDefaults,
                          BOOL skipDefaults) {
    for (size_t i = 0; i < count; ++i) {
        NSString *name = [NSString stringWithUTF8String:specs[i].name];
        if (skipDefaults &&
            parameter_name_is_default(name, availableDefaults)) {
            continue;
        }
        NSString *explanation =
            [NSString stringWithUTF8String:specs[i].explanation];
        [definitions addObject:parameter_definition(
                                   name, explanation, specs[i].minimum,
                                   specs[i].maximum, specs[i].defaultValue)];
    }
}

static NSDictionary *parameter_value(NSString *id, float value) {
    return @{
        @"id" : id,
        @"value" : json_float(value),
        @"weight" : @1.0,
    };
}

typedef struct {
    const char *name;
    float value;
} VTSAppleCVAParameterValueSpec;

#define VTS_PARAMETER_VALUE(name, value) {#name, value}
#define VTS_VALUE_FROM_PARAMETER(name, explanation, min, max, def, value)      \
    VTS_PARAMETER_VALUE(name, value),

static void add_parameter_values(NSMutableArray *values,
                                 NSSet<NSString *> *availableDefaults,
                                 const VTSAppleCVAParameterValueSpec *specs,
                                 size_t count, BOOL onlyDefaults,
                                 BOOL skipDefaults) {
    for (size_t i = 0; i < count; ++i) {
        NSString *name = [NSString stringWithUTF8String:specs[i].name];
        const BOOL isDefault =
            parameter_name_is_default(name, availableDefaults);
        if ((onlyDefaults && !isDefault) || (skipDefaults && isDefault)) {
            continue;
        }
        [values addObject:parameter_value(name, specs[i].value)];
    }
}

static BOOL matrix_has_signal(const float values[9]) {
    for (size_t i = 0; i < 9; ++i) {
        if (isfinite(values[i]) && fabsf(values[i]) > 0.000001f) {
            return YES;
        }
    }
    return NO;
}

static void rotation_matrix_to_degrees(const float values[9], float *outPitch,
                                       float *outYaw, float *outRoll) {
    /*
     * AppleCVA's face pose matrix is emitted in the opposite convention from
     * the standard row-major ZYX extraction used by ARKit/VTS consumers.
     */
    const float sy = sqrtf((values[0] * values[0]) + (values[1] * values[1]));
    const BOOL singular = sy < 1e-6f;
    float pitch = 0.0f;
    float yaw = 0.0f;
    float roll = 0.0f;

    if (!singular) {
        pitch = atan2f(values[5], values[8]);
        yaw = atan2f(-values[2], sy);
        roll = atan2f(values[1], values[0]);
    } else {
        pitch = atan2f(-values[7], values[4]);
        yaw = atan2f(-values[2], sy);
        roll = 0.0f;
    }

    const float radiansToDegrees = 180.0f / (float)M_PI;
    *outPitch = pitch * radiansToDegrees;
    *outYaw = yaw * radiansToDegrees;
    *outRoll = roll * radiansToDegrees;
}

static BOOL landmark_point(const AppleCVATrackedFace *face, size_t index,
                           AppleCVALandmarkPoint *outPoint) {
    if (face == NULL || outPoint == NULL ||
        index >= face->landmark_pair_count || index >= APPLECVA_MAX_LANDMARKS) {
        return NO;
    }
    const size_t base = index * 2;
    if (base + 1 >= face->landmark_float_count ||
        base + 1 >= APPLECVA_MAX_LANDMARK_FLOATS) {
        return NO;
    }
    const float x = face->landmarks[base];
    const float y = face->landmarks[base + 1];
    if (!isfinite(x) || !isfinite(y)) {
        return NO;
    }
    outPoint->x = x;
    outPoint->y = y;
    return YES;
}

static AppleCVALandmarkPoint midpoint(AppleCVALandmarkPoint a,
                                      AppleCVALandmarkPoint b) {
    return (AppleCVALandmarkPoint){
        .x = (a.x + b.x) * 0.5f,
        .y = (a.y + b.y) * 0.5f,
    };
}

static float landmark_distance(AppleCVALandmarkPoint a,
                               AppleCVALandmarkPoint b) {
    const float dx = a.x - b.x;
    const float dy = a.y - b.y;
    return sqrtf((dx * dx) + (dy * dy));
}

static BOOL landmark_pair_midpoint(const AppleCVATrackedFace *face,
                                   size_t aIndex, size_t bIndex,
                                   AppleCVALandmarkPoint *outPoint) {
    AppleCVALandmarkPoint a;
    AppleCVALandmarkPoint b;
    if (!landmark_point(face, aIndex, &a) ||
        !landmark_point(face, bIndex, &b)) {
        return NO;
    }
    *outPoint = midpoint(a, b);
    return YES;
}

static float landmark_pitch_degrees(const AppleCVATrackedFace *face) {
    AppleCVALandmarkPoint rightEye;
    AppleCVALandmarkPoint leftEye;
    AppleCVALandmarkPoint noseTip;
    AppleCVALandmarkPoint chin;
    if (!landmark_pair_midpoint(face, VTSAppleCVALandmarkRightEyeOuterCorner,
                                VTSAppleCVALandmarkRightEyeInnerCorner,
                                &rightEye) ||
        !landmark_pair_midpoint(face, VTSAppleCVALandmarkLeftEyeOuterCorner,
                                VTSAppleCVALandmarkLeftEyeInnerCorner,
                                &leftEye) ||
        !landmark_point(face, VTSAppleCVALandmarkNoseRidgeTip, &noseTip) ||
        !landmark_point(face, VTSAppleCVALandmarkChinCenter, &chin)) {
        return NAN;
    }

    const AppleCVALandmarkPoint eyeCenter = midpoint(rightEye, leftEye);
    const float eyeToChin = chin.y - eyeCenter.y;
    const float eyeToNose = noseTip.y - eyeCenter.y;
    if (fabsf(eyeToChin) < 1.0f) {
        return NAN;
    }

    const float ratio = eyeToNose / eyeToChin;
    const float neutralRatio = 0.38f;
    float pitch = (neutralRatio - ratio) * 220.0f;
    if (fabsf(pitch) < 1.5f) {
        pitch = 0.0f;
    }
    return clampf(pitch, -45.0f, 45.0f);
}

static void face_rotation(const AppleCVATrackedFace *face, float *outPitch,
                          float *outYaw, float *outRoll) {
    *outPitch = 0.0f;
    *outYaw = 0.0f;
    *outRoll = 0.0f;
    if (face == NULL) {
        return;
    }

    const float *rotation = matrix_has_signal(face->smooth_rotation)
                                ? face->smooth_rotation
                                : face->raw_rotation;
    if (matrix_has_signal(rotation)) {
        rotation_matrix_to_degrees(rotation, outPitch, outYaw, outRoll);
    } else if (isfinite(face->angle_roll)) {
        *outRoll = face->angle_roll * (180.0f / (float)M_PI);
    }

    const float landmarkPitch = landmark_pitch_degrees(face);
    if (isfinite(landmarkPitch)) {
        *outPitch = landmarkPitch;
    }
}

static BOOL face_rect_values(const AppleCVATrackedFace *face, float *outCenterX,
                             float *outCenterY, float *outSize) {
    if (face == NULL) {
        return NO;
    }

    const float x = face->rect[0];
    const float y = face->rect[1];
    const float width = face->rect[2];
    const float height = face->rect[3];
    if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) ||
        width <= 0.0f || height <= 0.0f) {
        return NO;
    }

    if (outCenterX != NULL) {
        *outCenterX = x + (width * 0.5f);
    }
    if (outCenterY != NULL) {
        *outCenterY = y + (height * 0.5f);
    }
    if (outSize != NULL) {
        *outSize = sqrtf(width * height);
    }
    return YES;
}

static void
calibrated_face_position_values(const AppleCVATrackedFace *face,
                                const VTSAppleCVACalibration *calibration,
                                float *outX, float *outY, float *outZ) {
    if (outX != NULL) {
        *outX = 0.0f;
    }
    if (outY != NULL) {
        *outY = 0.0f;
    }
    if (outZ != NULL) {
        *outZ = 0.0f;
    }
    if (face == NULL || calibration == NULL || !calibration->valid) {
        return;
    }

    float centerX = 0.0f;
    float centerY = 0.0f;
    float size = 0.0f;
    if (!face_rect_values(face, &centerX, &centerY, &size)) {
        return;
    }

    if (outX != NULL) {
        *outX = clampf((centerX - calibration->facePositionXZero) * 20.0f,
                       -10.0f, 10.0f);
    }
    if (outY != NULL) {
        *outY = clampf((centerY - calibration->facePositionYZero) * 20.0f,
                       -10.0f, 10.0f);
    }
    if (outZ != NULL && calibration->facePositionZNeutral > 0.0001f) {
        *outZ =
            clampf((1.0f - (size / calibration->facePositionZNeutral)) * 10.0f,
                   -10.0f, 10.0f);
    }
}

static float blendshape_at(const AppleCVATrackedFace *face, size_t index) {
    if (face == NULL || index >= face->blendshape_count ||
        index >= APPLECVA_MAX_BLENDSHAPES) {
        return 0.0f;
    }
    return clamp01(face->blendshapes[index]);
}

static float
adjusted_blendshape_value(const AppleCVATrackedFace *face,
                          size_t blendshapeIndex,
                          const VTSAppleCVASensitivityParameters *sensitivity) {
    const float value = blendshape_at(face, blendshapeIndex);
    if (sensitivity == NULL) {
        return value;
    }
    switch (blendshapeIndex) {
    case VTSAppleCVABlendshapeEyeBlinkLeft:
    case VTSAppleCVABlendshapeEyeBlinkRight:
        return apply_zero_based_sensitivity(value, sensitivity->blink);
    case VTSAppleCVABlendshapeEyeWideLeft:
    case VTSAppleCVABlendshapeEyeWideRight:
        return apply_zero_based_sensitivity(value, sensitivity->eyeOpen);
    case VTSAppleCVABlendshapeBrowDownLeft:
    case VTSAppleCVABlendshapeBrowDownRight:
    case VTSAppleCVABlendshapeBrowInnerUp:
    case VTSAppleCVABlendshapeBrowOuterUpLeft:
    case VTSAppleCVABlendshapeBrowOuterUpRight:
        return apply_zero_based_sensitivity(value, sensitivity->brow);
    case VTSAppleCVABlendshapeJawOpen:
        return apply_zero_based_sensitivity(value, sensitivity->mouthOpen);
    case VTSAppleCVABlendshapeMouthSmileLeft:
    case VTSAppleCVABlendshapeMouthSmileRight:
        return apply_zero_based_sensitivity(value, sensitivity->mouthSmile);
    default:
        return value;
    }
}

static float eye_open_from_landmarks(const AppleCVATrackedFace *face,
                                     BOOL leftEye) {
    const VTSAppleCVAEyeLandmarkIndices *eye = eye_landmarks(leftEye);
    AppleCVALandmarkPoint outer;
    AppleCVALandmarkPoint inner;
    AppleCVALandmarkPoint lowerOuter;
    AppleCVALandmarkPoint lowerInner;
    AppleCVALandmarkPoint upperOuter;
    AppleCVALandmarkPoint upperInner;
    if (!landmark_point(face, eye->outer, &outer) ||
        !landmark_point(face, eye->inner, &inner) ||
        !landmark_point(face, eye->lowerOuter, &lowerOuter) ||
        !landmark_point(face, eye->lowerInner, &lowerInner) ||
        !landmark_point(face, eye->upperOuter, &upperOuter) ||
        !landmark_point(face, eye->upperInner, &upperInner)) {
        return NAN;
    }

    const float width = landmark_distance(outer, inner);
    if (width < 1.0f) {
        return NAN;
    }
    const float outerAperture = landmark_distance(upperOuter, lowerOuter);
    const float innerAperture = landmark_distance(upperInner, lowerInner);
    const float ratio = ((outerAperture + innerAperture) * 0.5f) / width;
    return remap_clamped(ratio, 0.03f, 0.19f, 0.0f, 1.0f);
}

static float eye_open_measurement(const AppleCVATrackedFace *face,
                                  BOOL leftEye) {
    if (face == NULL) {
        return 1.0f;
    }

    const VTSAppleCVASideBlendshapeIndices *side = side_blendshapes(leftEye);
    const float blinkClosed = remap_clamped(blendshape_at(face, side->blink),
                                            0.06f, 0.45f, 0.0f, 1.0f);
    const float blendOpen = 1.0f - blinkClosed;
    const float landmarkOpen = eye_open_from_landmarks(face, leftEye);
    float value =
        isfinite(landmarkOpen) ? fminf(landmarkOpen, blendOpen) : blendOpen;
    if (blinkClosed < 0.2f) {
        value += blendshape_at(face, side->wide) * 0.15f;
    }
    return clamp01(value);
}

static float
eye_open_value(const AppleCVATrackedFace *face, BOOL leftEye,
               const VTSAppleCVACalibration *calibration,
               const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 1.0f;
    }
    const float value = eye_open_measurement(face, leftEye);
    if (sensitivity == NULL) {
        return value;
    }

    float neutral = 1.0f;
    if (calibration != NULL && calibration->valid) {
        neutral = leftEye ? calibration->eyeOpenLeftNeutral
                          : calibration->eyeOpenRightNeutral;
        neutral = clampf(neutral, 0.05f, 1.0f);
    }
    if (value < neutral) {
        return apply_centered_sensitivity(value, neutral, sensitivity->blink,
                                          0.0f, 1.0f);
    }
    return apply_centered_sensitivity(value, neutral, sensitivity->eyeOpen,
                                      0.0f, 1.0f);
}

static float eye_narrowing_value(const AppleCVATrackedFace *face, BOOL leftEye,
                                 const VTSAppleCVACalibration *calibration) {
    if (face == NULL) {
        return 0.0f;
    }

    float neutral = 1.0f;
    if (calibration != NULL && calibration->valid) {
        neutral = leftEye ? calibration->eyeOpenLeftNeutral
                          : calibration->eyeOpenRightNeutral;
        neutral = clampf(neutral, 0.05f, 1.0f);
    }

    const float measurement = eye_open_measurement(face, leftEye);
    const float narrowing = clamp01(neutral - measurement);
    const float scale = fmaxf(0.12f, neutral * 0.35f);
    return remap_clamped(narrowing, 0.03f, scale, 0.0f, 1.0f);
}

static float mouth_open_value(const AppleCVATrackedFace *face) {
    if (face == NULL) {
        return 0.0f;
    }
    return blendshape_at(face, VTSAppleCVABlendshapeJawOpen);
}

static float calibrated_mouth_open_value(
    const AppleCVATrackedFace *face, const VTSAppleCVACalibration *calibration,
    const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 0.0f;
    }
    if (calibration == NULL || !calibration->valid) {
        return 0.0f;
    }
    const float openStart =
        clampf(calibration->jawOpenNeutral + 0.08f, 0.0f, 0.95f);
    float mouthOpen =
        remap_clamped(blendshape_at(face, VTSAppleCVABlendshapeJawOpen),
                      openStart, 1.0f, 0.0f, 1.0f);

    const float mouthClose =
        blendshape_at(face, VTSAppleCVABlendshapeMouthClose);
    if (mouthClose > 0.2f) {
        mouthOpen *= 1.0f - remap_clamped(mouthClose, 0.2f, 0.8f, 0.0f, 1.0f);
    }
    return apply_zero_based_sensitivity(
        mouthOpen,
        sensitivity != NULL ? sensitivity->mouthOpen : kVTSSensitivityDefault);
}

static float brow_y_value(const AppleCVATrackedFace *face, BOOL leftBrow,
                          const VTSAppleCVACalibration *calibration,
                          const VTSAppleCVASensitivityParameters *sensitivity);

void VTSAppleCVACalibrationInit(VTSAppleCVACalibration *calibration) {
    if (calibration != NULL) {
        memset(calibration, 0, sizeof(*calibration));
    }
}

BOOL VTSAppleCVAObservedValuesFromFace(const AppleCVATrackedFace *face,
                                       BOOL faceFound,
                                       VTSAppleCVAObservedValues *outValues) {
    if (outValues == NULL) {
        return NO;
    }
    memset(outValues, 0, sizeof(*outValues));
    if (!faceFound || face == NULL) {
        return NO;
    }

    float pitch = 0.0f;
    float yaw = 0.0f;
    float roll = 0.0f;
    face_rotation(face, &pitch, &yaw, &roll);

    outValues->valid = true;
    outValues->faceAngleX = clampf(-yaw, -45.0f, 45.0f);
    outValues->faceAngleY = clampf(pitch, -45.0f, 45.0f);
    outValues->faceAngleZ = clampf(roll, -45.0f, 45.0f);
    face_rect_values(face, &outValues->facePositionX, &outValues->facePositionY,
                     &outValues->facePositionZ);
    outValues->jawOpen = blendshape_at(face, VTSAppleCVABlendshapeJawOpen);
    outValues->mouthOpen = mouth_open_value(face);
    outValues->eyeOpenLeft = eye_open_value(face, YES, NULL, NULL);
    outValues->eyeOpenRight = eye_open_value(face, NO, NULL, NULL);
    outValues->browLeftY = brow_y_value(face, YES, NULL, NULL);
    outValues->browRightY = brow_y_value(face, NO, NULL, NULL);
    return YES;
}

void VTSAppleCVACalibrationFromObservedSamples(
    const VTSAppleCVAObservedValues *samples, size_t sampleCount,
    VTSAppleCVACalibration *outCalibration) {
    if (outCalibration == NULL) {
        return;
    }
    VTSAppleCVACalibrationInit(outCalibration);
    if (samples == NULL || sampleCount == 0) {
        return;
    }

    size_t count = 0;
    VTSAppleCVACalibration sum;
    VTSAppleCVACalibrationInit(&sum);
    for (size_t i = 0; i < sampleCount; ++i) {
        if (!samples[i].valid) {
            continue;
        }
#define VTS_ACCUMULATE_CALIBRATION_FIELD(zero, observed)                       \
    sum.zero += samples[i].observed;
        VTS_APPLECVA_CALIBRATION_FIELDS(VTS_ACCUMULATE_CALIBRATION_FIELD)
#undef VTS_ACCUMULATE_CALIBRATION_FIELD
        ++count;
    }
    if (count == 0) {
        return;
    }

    const float scale = 1.0f / (float)count;
    outCalibration->valid = true;
#define VTS_STORE_CALIBRATION_FIELD(zero, observed)                            \
    outCalibration->zero = sum.zero * scale;
    VTS_APPLECVA_CALIBRATION_FIELDS(VTS_STORE_CALIBRATION_FIELD)
#undef VTS_STORE_CALIBRATION_FIELD
}

static float
mouth_smile_side_value(const AppleCVATrackedFace *face, BOOL leftSide,
                       const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 0.0f;
    }
    const VTSAppleCVASideBlendshapeIndices *side = side_blendshapes(leftSide);
    const float smile = blendshape_at(face, side->mouthSmile);
    const float frown = blendshape_at(face, side->mouthFrown);
    return apply_zero_based_sensitivity(
        smile - (frown * 0.35f),
        sensitivity != NULL ? sensitivity->mouthSmile : kVTSSensitivityDefault);
}

static float
mouth_smile_value(const AppleCVATrackedFace *face,
                  const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 0.0f;
    }
    const float smile =
        (blendshape_at(face, VTSAppleCVABlendshapeMouthSmileLeft) +
         blendshape_at(face, VTSAppleCVABlendshapeMouthSmileRight)) *
        0.5f;
    const float frown =
        (blendshape_at(face, VTSAppleCVABlendshapeMouthFrownLeft) +
         blendshape_at(face, VTSAppleCVABlendshapeMouthFrownRight)) *
        0.5f;
    return apply_zero_based_sensitivity(
        smile - (frown * 0.35f),
        sensitivity != NULL ? sensitivity->mouthSmile : kVTSSensitivityDefault);
}

static float
eye_smile_value(const AppleCVATrackedFace *face, BOOL leftEye,
                const VTSAppleCVACalibration *calibration,
                const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 0.0f;
    }

    const VTSAppleCVASideBlendshapeIndices *side = side_blendshapes(leftEye);
    const float mouthSmile = mouth_smile_side_value(face, leftEye, sensitivity);
    const float eyeSquint = blendshape_at(face, side->squint);
    const float cheekSquint = blendshape_at(face, side->cheekSquint);
    const float mouthFrown = blendshape_at(face, side->mouthFrown);
    const float browDown = blendshape_at(face, side->browDown);
    const float blink = blendshape_at(face, side->blink);
    const float narrowing = eye_narrowing_value(face, leftEye, calibration);
    const float smileGate = remap_clamped(mouthSmile, 0.08f, 0.62f, 0.0f, 1.0f);
    const float eyeGate = remap_clamped(
        (eyeSquint * 0.45f) + (cheekSquint * 0.35f) + (narrowing * 0.20f),
        0.10f, 0.55f, 0.0f, 1.0f);
    const float browPenalty =
        1.0f - remap_clamped(browDown, 0.15f, 0.65f, 0.0f, 0.90f);
    const float blinkPenalty =
        1.0f - remap_clamped(blink, 0.55f, 0.92f, 0.0f, 1.0f);
    const float frownPenalty =
        1.0f - remap_clamped(mouthFrown, 0.08f, 0.45f, 0.0f, 0.85f);
    return clamp01(smileGate * eyeGate * browPenalty * blinkPenalty *
                   frownPenalty);
}

static float blush_when_smiling_value(float mouthSmile) {
    return clamp01(mouthSmile);
}

static float mouth_x_value(const AppleCVATrackedFace *face) {
    if (face == NULL) {
        return 0.0f;
    }
    return clampf(blendshape_at(face, VTSAppleCVABlendshapeMouthRight) -
                      blendshape_at(face, VTSAppleCVABlendshapeMouthLeft),
                  -1.0f, 1.0f);
}

static float brow_y_value(const AppleCVATrackedFace *face, BOOL leftBrow,
                          const VTSAppleCVACalibration *calibration,
                          const VTSAppleCVASensitivityParameters *sensitivity) {
    if (face == NULL) {
        return 0.5f;
    }
    const VTSAppleCVASideBlendshapeIndices *side = side_blendshapes(leftBrow);
    const float browDown = blendshape_at(face, side->browDown);
    const float outerUp = blendshape_at(face, side->browOuterUp);
    const float innerUp = blendshape_at(face, VTSAppleCVABlendshapeBrowInnerUp);
    const float value =
        clamp01(0.5f + (((outerUp + innerUp) * 0.5f - browDown) * 0.5f));
    float neutral = 0.5f;
    if (calibration != NULL && calibration->valid) {
        neutral = leftBrow ? calibration->browLeftYNeutral
                           : calibration->browRightYNeutral;
        neutral = clamp01(neutral);
    }
    return apply_centered_sensitivity(
        value, neutral,
        sensitivity != NULL ? sensitivity->brow : kVTSSensitivityDefault, 0.0f,
        1.0f);
}

static float eye_degrees_to_vts(float radians) {
    if (!isfinite(radians)) {
        return 0.0f;
    }
    return clampf(radians * (180.0f / (float)M_PI) / 30.0f, -1.0f, 1.0f);
}

static float eye_radians_to_acva_degrees(float radians) {
    if (!isfinite(radians)) {
        return 0.0f;
    }
    return clampf(radians * (180.0f / (float)M_PI), -45.0f, 45.0f);
}

NSArray<NSDictionary *> *
VTSAppleCVACustomParameterDefinitions(BOOL includeARKitAliases,
                                      BOOL includeACVABlendshapeParameters,
                                      NSSet<NSString *> *availableDefaults) {
    NSMutableArray *definitions =
        [NSMutableArray arrayWithCapacity:kVTSMaxCustomParameters];
    add_parameter_definitions(definitions, kACVADerivedParameterDefinitions,
                              ARRAY_COUNT(kACVADerivedParameterDefinitions),
                              nil, NO);
    add_parameter_definitions(definitions, kSpecialVTSParameterDefinitions,
                              ARRAY_COUNT(kSpecialVTSParameterDefinitions),
                              availableDefaults, YES);
    if (includeARKitAliases) {
        for (size_t i = 0; i < ARRAY_COUNT(kARKitAliasParameters); ++i) {
            const VTSAppleCVAIndexedParameterName alias =
                kARKitAliasParameters[i];
            NSString *name = [NSString stringWithUTF8String:alias.name];
            if (parameter_name_is_default(name, availableDefaults)) {
                continue;
            }
            NSString *explanation = [NSString
                stringWithFormat:@"AppleCVA ARKit alias for %s",
                                 AppleCVABlendshapeNames[alias
                                                             .blendshapeIndex]];
            [definitions addObject:parameter_definition(name, explanation, 0.0f,
                                                        1.0f, 0.0f)];
        }
    }
    const size_t acvaBlendshapeCount = acva_blendshape_parameter_count(
        includeARKitAliases, includeACVABlendshapeParameters,
        availableDefaults);
    if (includeACVABlendshapeParameters) {
        log_dropped_acva_blendshape_parameters(acvaBlendshapeCount);
    }
    for (size_t i = 0; i < acvaBlendshapeCount; ++i) {
        NSString *name =
            [NSString stringWithUTF8String:kCustomBlendshapeNames[i]];
        NSString *explanation =
            [NSString stringWithFormat:@"AppleCVA ARKit channel %s",
                                       AppleCVABlendshapeNames[i]];
        [definitions addObject:parameter_definition(name, explanation, 0.0f,
                                                    1.0f, 0.0f)];
    }
    return definitions;
}

NSArray<NSDictionary *> *VTSAppleCVAParameterValues(
    const AppleCVATrackedFace *face, BOOL faceFound,
    NSSet<NSString *> *availableDefaultParameters,
    const VTSAppleCVACalibration *calibration,
    const VTSAppleCVASensitivityParameters *sensitivityParameters,
    BOOL includeCustomParameters, BOOL includeARKitAliases,
    BOOL includeACVABlendshapeParameters) {
    if (!faceFound) {
        face = NULL;
    }

    VTSAppleCVASensitivityParameters sensitivity =
        VTSAppleCVASensitivityParametersDefault();
    if (sensitivityParameters != NULL) {
        sensitivity =
            VTSAppleCVASensitivityParametersSanitize(*sensitivityParameters);
    }

    NSMutableArray *values =
        [NSMutableArray arrayWithCapacity:APPLECVA_MAX_BLENDSHAPES + 64];

    VTSAppleCVAObservedValues observed;
    VTSAppleCVAObservedValuesFromFace(face, face != NULL, &observed);
    float yaw = observed.faceAngleX;
    float pitch = observed.faceAngleY;
    float roll = observed.faceAngleZ;
    if (calibration != NULL && calibration->valid) {
        yaw -= calibration->faceAngleXZero;
        pitch -= calibration->faceAngleYZero;
        roll -= calibration->faceAngleZZero;
    }
    yaw = clampf(yaw, -45.0f, 45.0f);
    pitch = clampf(pitch * 1.35f, -45.0f, 45.0f);
    roll = clampf(roll, -45.0f, 45.0f);
    float facePositionX = 0.0f;
    float facePositionY = 0.0f;
    float facePositionZ = 0.0f;
    calibrated_face_position_values(face, calibration, &facePositionX,
                                    &facePositionY, &facePositionZ);
    const float eyeOpenLeft =
        eye_open_value(face, YES, calibration, &sensitivity);
    const float eyeOpenRight =
        eye_open_value(face, NO, calibration, &sensitivity);
    const float mouthOpen =
        calibrated_mouth_open_value(face, calibration, &sensitivity);
    const float mouthSmile = mouth_smile_value(face, &sensitivity);
    const float eyeSmileLeft =
        eye_smile_value(face, YES, calibration, &sensitivity);
    const float eyeSmileRight =
        eye_smile_value(face, NO, calibration, &sensitivity);
    const float blushWhenSmiling = blush_when_smiling_value(mouthSmile);
    const float mouthX = mouth_x_value(face);
    const float browLeftY = brow_y_value(face, YES, calibration, &sensitivity);
    const float browRightY = brow_y_value(face, NO, calibration, &sensitivity);
    const float eyeLeftX =
        face != NULL ? eye_degrees_to_vts(face->left_eye_yaw) : 0.0f;
    const float eyeLeftY =
        face != NULL ? eye_degrees_to_vts(face->left_eye_pitch) : 0.0f;
    const float eyeRightX =
        face != NULL ? eye_degrees_to_vts(face->right_eye_yaw) : 0.0f;
    const float eyeRightY =
        face != NULL ? eye_degrees_to_vts(face->right_eye_pitch) : 0.0f;
    const float tongueOut = face != NULL ? clamp01(face->tongue_out) : 0.0f;
    const float acvaEyeLeftX =
        face != NULL ? eye_radians_to_acva_degrees(face->left_eye_yaw) : 0.0f;
    const float acvaEyeLeftY =
        face != NULL ? eye_radians_to_acva_degrees(face->left_eye_pitch) : 0.0f;
    const float acvaEyeRightX =
        face != NULL ? eye_radians_to_acva_degrees(face->right_eye_yaw) : 0.0f;
    const float acvaEyeRightY =
        face != NULL ? eye_radians_to_acva_degrees(face->right_eye_pitch)
                     : 0.0f;

    if (availableDefaultParameters != nil) {
        const VTSAppleCVAParameterValueSpec defaultValues[] = {
            VTS_PARAMETER_VALUE(FaceAngleX, yaw),
            VTS_PARAMETER_VALUE(FaceAngleY, pitch),
            VTS_PARAMETER_VALUE(FaceAngleZ, roll),
            VTS_PARAMETER_VALUE(FacePositionX, facePositionX),
            VTS_PARAMETER_VALUE(FacePositionY, facePositionY),
            VTS_PARAMETER_VALUE(FacePositionZ, facePositionZ),
            VTS_PARAMETER_VALUE(EyeOpenLeft, eyeOpenLeft),
            VTS_PARAMETER_VALUE(EyeOpenRight, eyeOpenRight),
            VTS_PARAMETER_VALUE(EyeLeftX, eyeLeftX),
            VTS_PARAMETER_VALUE(EyeLeftY, eyeLeftY),
            VTS_PARAMETER_VALUE(EyeRightX, eyeRightX),
            VTS_PARAMETER_VALUE(EyeRightY, eyeRightY),
            VTS_PARAMETER_VALUE(MouthOpen, mouthOpen),
            VTS_PARAMETER_VALUE(MouthSmile, mouthSmile),
            VTS_PARAMETER_VALUE(EyeSmileLeft, eyeSmileLeft),
            VTS_PARAMETER_VALUE(EyeSmileRight, eyeSmileRight),
            VTS_PARAMETER_VALUE(BlushWhenSmiling, blushWhenSmiling),
            VTS_PARAMETER_VALUE(MouthX, mouthX),
            VTS_PARAMETER_VALUE(Brows, (browLeftY + browRightY) * 0.5f),
            VTS_PARAMETER_VALUE(BrowLeftY, browLeftY),
            VTS_PARAMETER_VALUE(BrowRightY, browRightY),
            VTS_PARAMETER_VALUE(TongueOut, tongueOut),
        };
        add_parameter_values(values, availableDefaultParameters, defaultValues,
                             ARRAY_COUNT(defaultValues), YES, NO);
        if (!includeCustomParameters || !includeARKitAliases) {
            const VTSAppleCVAParameterValueSpec cheekPuffValue[] = {
                VTS_PARAMETER_VALUE(
                    CheekPuff,
                    blendshape_at(face, VTSAppleCVABlendshapeCheekPuff)),
            };
            add_parameter_values(values, availableDefaultParameters,
                                 cheekPuffValue, ARRAY_COUNT(cheekPuffValue),
                                 YES, NO);
        }
    }

    if (!includeCustomParameters) {
        return values;
    }

    const VTSAppleCVAParameterValueSpec specialValues[] = {
        VTS_SPECIAL_PARAMETERS(VTS_VALUE_FROM_PARAMETER)};
    add_parameter_values(values, availableDefaultParameters, specialValues,
                         ARRAY_COUNT(specialValues), NO, YES);

    if (includeARKitAliases) {
        for (size_t i = 0; i < ARRAY_COUNT(kARKitAliasParameters); ++i) {
            const VTSAppleCVAIndexedParameterName alias =
                kARKitAliasParameters[i];
            NSString *name = [NSString stringWithUTF8String:alias.name];
            [values
                addObject:parameter_value(name, adjusted_blendshape_value(
                                                    face, alias.blendshapeIndex,
                                                    &sensitivity))];
        }
    }

    const size_t acvaBlendshapeCount = acva_blendshape_parameter_count(
        includeARKitAliases, includeACVABlendshapeParameters,
        availableDefaultParameters);
    for (size_t i = 0; i < acvaBlendshapeCount; ++i) {
        NSString *name =
            [NSString stringWithUTF8String:kCustomBlendshapeNames[i]];
        [values addObject:parameter_value(name, blendshape_at(face, i))];
    }
    const VTSAppleCVAParameterValueSpec acvaValues[] = {
        VTS_ACVA_DERIVED_PARAMETERS(VTS_VALUE_FROM_PARAMETER)};
    add_parameter_values(values, nil, acvaValues, ARRAY_COUNT(acvaValues), NO,
                         NO);
    return values;
}
