#import "calibration.h"

#include <string.h>

static const size_t kVTSCalibrationSampleTarget = 45;

@implementation VTSCalibrationController {
    BOOL _calibrated;
    BOOL _inProgress;
    size_t _sampleCount;
    VTSAppleCVAObservedValues _samples[45];
    VTSAppleCVACalibration _calibration;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        VTSAppleCVACalibrationInit(&_calibration);
    }
    return self;
}

- (BOOL)calibrated {
    @synchronized(self) {
        return _calibrated && !_inProgress && _calibration.valid;
    }
}

- (BOOL)inProgress {
    @synchronized(self) {
        return _inProgress;
    }
}

- (size_t)sampleCount {
    @synchronized(self) {
        return _sampleCount;
    }
}

- (size_t)sampleTarget {
    return kVTSCalibrationSampleTarget;
}

- (VTSAppleCVACalibration)calibration {
    @synchronized(self) {
        return _calibration;
    }
}

- (void)startCalibration {
    @synchronized(self) {
        _calibrated = NO;
        _inProgress = YES;
        _sampleCount = 0;
        memset(_samples, 0, sizeof(_samples));
        VTSAppleCVACalibrationInit(&_calibration);
    }
}

- (BOOL)collectSampleFromFace:(const AppleCVATrackedFace *)face
                      hasFace:(BOOL)hasFace {
    @synchronized(self) {
        if (!_inProgress || _sampleCount >= kVTSCalibrationSampleTarget) {
            return NO;
        }

        VTSAppleCVAObservedValues values;
        if (!VTSAppleCVAObservedValuesFromFace(face, hasFace, &values)) {
            return NO;
        }

        _samples[_sampleCount++] = values;
        if (_sampleCount < kVTSCalibrationSampleTarget) {
            return NO;
        }

        VTSAppleCVACalibrationFromObservedSamples(_samples, _sampleCount,
                                                  &_calibration);
        _calibrated = _calibration.valid;
        _inProgress = NO;
        return _calibrated;
    }
}

- (NSString *)statusLine {
    @synchronized(self) {
        if (_inProgress) {
            return [NSString
                stringWithFormat:
                    @"calibration %zu/%zu: relax mouth and look straight",
                    _sampleCount, kVTSCalibrationSampleTarget];
        }
        if (_calibrated && _calibration.valid) {
            return [NSString
                stringWithFormat:
                    @"calibrated yaw %.1f pitch %.1f roll %.1f jaw %.2f",
                    _calibration.faceAngleXZero, _calibration.faceAngleYZero,
                    _calibration.faceAngleZZero, _calibration.jawOpenNeutral];
        }
        return @"calibration required: press Calibrate before VTS connects";
    }
}

@end
