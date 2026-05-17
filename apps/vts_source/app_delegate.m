#import "app_delegate.h"

#import "calibration.h"
#import "client.h"
#import "overlay_view.h"
#import "parameters.h"
#import "tracking_pipeline.h"

#import <Foundation/Foundation.h>

static float parameter_value_for_id(NSArray<NSDictionary *> *parameterValues,
                                    NSString *parameterID, BOOL *outFound) {
    if (outFound != NULL) {
        *outFound = NO;
    }
    for (NSDictionary *parameter in parameterValues) {
        if (![parameter isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSString *candidateID = parameter[@"id"];
        if (![candidateID isKindOfClass:NSString.class] ||
            ![candidateID isEqualToString:parameterID]) {
            continue;
        }
        NSNumber *value = parameter[@"value"];
        if (![value isKindOfClass:NSNumber.class]) {
            continue;
        }
        if (outFound != NULL) {
            *outFound = YES;
        }
        return value.floatValue;
    }
    return 0.0f;
}

@implementation VTSAppDelegate {
    NSString *_host;
    uint16_t _port;
    BOOL _useFullBackend;
    BOOL _enableFilter;
    BOOL _includeCustomParameters;
    NSWindow *_window;
    AppleCVAOverlayView *_view;
    AppleCVATrackingPipeline *_pipeline;
    VTSCalibrationController *_calibrationController;
    VTSClient *_vtsClient;
}

- (instancetype)initWithHost:(NSString *)host
                        port:(uint16_t)port
              useFullBackend:(BOOL)useFullBackend
                enableFilter:(BOOL)enableFilter
     includeCustomParameters:(BOOL)includeCustomParameters {
    self = [super init];
    if (self != nil) {
        _host = [host copy] ?: @"127.0.0.1";
        _port = port;
        _useFullBackend = useFullBackend;
        _enableFilter = enableFilter;
        _includeCustomParameters = includeCustomParameters;
        _calibrationController = [[VTSCalibrationController alloc] init];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    _view = [[AppleCVAOverlayView alloc]
        initWithFrame:NSMakeRect(0.0, 0.0, 960.0, 720.0)];
    _view.useFullBackend = _useFullBackend;
    _view.useOneEuroFilter = _enableFilter;
    _view.showsCalibrationButton = YES;
    _view.calibrationButtonTitle = @"Calibrate First";
    _view.calibrationButtonEnabled = YES;
    [_view setCalibrationTarget:self action:@selector(startCalibration:)];

    _window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(140.0, 120.0, 960.0, 720.0)
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable |
                            NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _window.title = @"AppleCVA VTS Source";
    _window.contentView = _view;
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    __weak VTSAppDelegate *weakSelf = self;
    _view.settingsChangedHandler = ^(AppleCVAOverlayView *view) {
      VTSAppDelegate *strongSelf = weakSelf;
      if (strongSelf == nil) {
          return;
      }
      strongSelf->_pipeline.useOneEuroFilter = view.useOneEuroFilter;
    };

    _pipeline = [[AppleCVATrackingPipeline alloc]
        initWithFullBackend:_useFullBackend
          captureQueueLabel:@"local.applecva.vts-source.capture"];
    _pipeline.useOneEuroFilter = _enableFilter;
    _pipeline.statusHandler = ^(NSString *message, int32_t status) {
      [weakSelf handlePipelineStatusMessage:message status:status];
    };
    _pipeline.frameHandler =
        ^(CVPixelBufferRef pixelBuffer, const AppleCVATrackedFace *face,
          BOOL hasFace, size_t detectedFaceCount, size_t trackedFaceCount,
          int32_t status, double timestamp, double fps) {
          (void)timestamp;
          [weakSelf handleTrackingPixelBuffer:pixelBuffer
                                         face:face
                                      hasFace:hasFace
                            detectedFaceCount:detectedFaceCount
                             trackedFaceCount:trackedFaceCount
                                       status:status
                                          fps:fps];
        };

    [_view
        updateWithPixelBuffer:NULL
                         face:NULL
                      hasFace:NO
            detectedFaceCount:0
             trackedFaceCount:0
                   lastStatus:APPLECVA_OK
                      message:@"Calibration required."
              extraStatusLine:[self
                                  currentExtraStatusLineWithParameterValues:nil]
                          fps:0.0];
    [_pipeline start];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:
    (NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [_pipeline stop];
    [self stopVTSClient];
}

- (void)startCalibration:(id)sender {
    (void)sender;
    [_calibrationController startCalibration];
    [self stopVTSClient];
    [self updateCalibrationControlOnMain];
    dispatch_async(dispatch_get_main_queue(), ^{
      self->_view.needsDisplay = YES;
    });
}

- (void)handlePipelineStatusMessage:(NSString *)message status:(int32_t)status {
    [_view
        updateWithPixelBuffer:NULL
                         face:NULL
                      hasFace:NO
            detectedFaceCount:0
             trackedFaceCount:0
                   lastStatus:status
                      message:message ?: @""
              extraStatusLine:[self
                                  currentExtraStatusLineWithParameterValues:nil]
                          fps:0.0];
}

- (void)handleTrackingPixelBuffer:(CVPixelBufferRef)pixelBuffer
                             face:(const AppleCVATrackedFace *)face
                          hasFace:(BOOL)hasFace
                detectedFaceCount:(size_t)detectedFaceCount
                 trackedFaceCount:(size_t)trackedFaceCount
                           status:(int32_t)status
                              fps:(double)fps {
    const BOOL calibrationCompleted =
        [_calibrationController collectSampleFromFace:face hasFace:hasFace];
    if (calibrationCompleted) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self updateCalibrationControlOnMain];
        });
    }

    VTSClient *client = nil;
    NSArray<NSDictionary *> *parameterValues = nil;
    VTSAppleCVACalibration calibrationSnapshot =
        _calibrationController.calibration;
    const BOOL calibrated = _calibrationController.calibrated;
    if (calibrated) {
        client = [self ensureVTSClientStartedIfNeeded];
        NSSet<NSString *> *defaultParameterNames =
            [client defaultParameterNamesSnapshot];
        parameterValues = VTSAppleCVAParameterValues(
            face, hasFace, defaultParameterNames, &calibrationSnapshot,
            _includeCustomParameters);
        [client injectParameterValues:parameterValues faceFound:hasFace];
    }

    NSString *message = [self displayMessageForFaceFound:hasFace
                                              calibrated:calibrated];
    NSString *extraStatusLine =
        [self currentExtraStatusLineWithParameterValues:parameterValues];
    const AppleCVATrackedFace faceSnapshot =
        face != NULL ? *face : (AppleCVATrackedFace){0};
    CVPixelBufferRetain(pixelBuffer);
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateCalibrationControlOnMain];
      [self->_view updateWithPixelBuffer:pixelBuffer
                                    face:hasFace ? &faceSnapshot : NULL
                                 hasFace:hasFace
                       detectedFaceCount:detectedFaceCount
                        trackedFaceCount:trackedFaceCount
                              lastStatus:status
                                 message:message
                         extraStatusLine:extraStatusLine
                                     fps:fps];
      CVPixelBufferRelease(pixelBuffer);
    });
}

- (NSString *)displayMessageForFaceFound:(BOOL)hasFace
                              calibrated:(BOOL)calibrated {
    if (calibrated) {
        return hasFace ? @"Tracking face." : @"Waiting for face...";
    }
    if (_calibrationController.inProgress) {
        return hasFace ? @"Calibrating neutral pose."
                       : @"Calibration waiting for face.";
    }
    return hasFace ? @"Press Calibrate to unlock VTS."
                   : @"Calibration required.";
}

- (VTSClient *)ensureVTSClientStartedIfNeeded {
    @synchronized(self) {
        if (_vtsClient == nil) {
            _vtsClient =
                [[VTSClient alloc] initWithHost:_host
                                           port:_port
                        includeCustomParameters:_includeCustomParameters];
            [_vtsClient start];
        }
        return _vtsClient;
    }
}

- (void)stopVTSClient {
    VTSClient *client = nil;
    @synchronized(self) {
        client = _vtsClient;
        _vtsClient = nil;
    }
    [client stop];
}

- (VTSClient *)currentVTSClient {
    @synchronized(self) {
        return _vtsClient;
    }
}

- (NSString *)currentExtraStatusLineWithParameterValues:
    (NSArray<NSDictionary *> *)parameterValues {
    NSString *customStatus =
        _includeCustomParameters ? @"custom on" : @"custom off";
    NSString *calibrationStatus = [_calibrationController statusLine];
    if (!_calibrationController.calibrated) {
        return [NSString stringWithFormat:@"vts locked  %@  %@", customStatus,
                                          calibrationStatus];
    }

    VTSClient *client = [self currentVTSClient];
    NSString *vtsStatus = client != nil ? [client statusLine] : @"vts starting";
    NSString *base =
        [NSString stringWithFormat:@"%@  %@  %@", vtsStatus, customStatus,
                                   calibrationStatus];
    if (parameterValues.count == 0) {
        return base;
    }

    BOOL hasMouth = NO;
    const float mouth =
        parameter_value_for_id(parameterValues, @"MouthOpen", &hasMouth);
    BOOL hasJaw = NO;
    const float jaw =
        parameter_value_for_id(parameterValues, @"ACVAJawOpen", &hasJaw);
    BOOL hasEyeLeft = NO;
    BOOL hasEyeRight = NO;
    BOOL hasYaw = NO;
    BOOL hasPitch = NO;
    const float eyeLeft =
        parameter_value_for_id(parameterValues, @"EyeOpenLeft", &hasEyeLeft);
    const float eyeRight =
        parameter_value_for_id(parameterValues, @"EyeOpenRight", &hasEyeRight);
    float yaw = parameter_value_for_id(parameterValues, @"FaceAngleX", &hasYaw);
    if (!hasYaw) {
        yaw =
            parameter_value_for_id(parameterValues, @"ACVAFaceAngleX", &hasYaw);
    }
    float pitch =
        parameter_value_for_id(parameterValues, @"FaceAngleY", &hasPitch);
    if (!hasPitch) {
        pitch = parameter_value_for_id(parameterValues, @"ACVAFaceAngleY",
                                       &hasPitch);
    }
    if (!hasMouth && !hasJaw && !hasEyeLeft && !hasEyeRight && !hasYaw &&
        !hasPitch) {
        return base;
    }
    return [base
        stringByAppendingFormat:@"  mouthVTS %@ jaw %@ eyeL %.2f eyeR %.2f "
                                @"yaw %.1f pitch %.1f",
                                hasMouth
                                    ? [NSString stringWithFormat:@"%.2f", mouth]
                                    : @"-",
                                hasJaw
                                    ? [NSString stringWithFormat:@"%.2f", jaw]
                                    : @"-",
                                eyeLeft, eyeRight, yaw, pitch];
}

- (void)updateCalibrationControlOnMain {
    if (_calibrationController.inProgress) {
        _view.calibrationButtonTitle = @"Calibrating...";
        _view.calibrationButtonEnabled = NO;
        return;
    }
    if (_calibrationController.calibrated) {
        _view.calibrationButtonTitle = @"Recalibrate";
        _view.calibrationButtonEnabled = YES;
        return;
    }
    _view.calibrationButtonTitle = @"Calibrate First";
    _view.calibrationButtonEnabled = YES;
}

@end
