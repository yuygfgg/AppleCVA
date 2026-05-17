#import "capture.h"

#include <math.h>

bool AppleCVACaptureCopyCameraIntrinsicsFromSampleBuffer(
    CMSampleBufferRef sample_buffer, AppleCVACameraParameters *params) {
    if (sample_buffer == NULL || params == NULL) {
        return false;
    }

    CFTypeRef attachment = CMGetAttachment(
        sample_buffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
        NULL);
    if (attachment == NULL || CFGetTypeID(attachment) != CFDataGetTypeID()) {
        return false;
    }

    CFDataRef matrix_data = (CFDataRef)attachment;
    if (CFDataGetLength(matrix_data) < (CFIndex)(sizeof(float) * 9)) {
        return false;
    }

    const float *columns = (const float *)CFDataGetBytePtr(matrix_data);
    if (columns == NULL) {
        return false;
    }

    params->intrinsics[0] = columns[0];
    params->intrinsics[1] = columns[3];
    params->intrinsics[2] = columns[6];
    params->intrinsics[3] = columns[1];
    params->intrinsics[4] = columns[4];
    params->intrinsics[5] = columns[7];
    params->intrinsics[6] = columns[2];
    params->intrinsics[7] = columns[5];
    params->intrinsics[8] = columns[8];
    return isfinite(params->intrinsics[0]) && params->intrinsics[0] > 0.0f &&
           isfinite(params->intrinsics[4]) && params->intrinsics[4] > 0.0f &&
           isfinite(params->intrinsics[8]) && params->intrinsics[8] != 0.0f;
}

void AppleCVACaptureUpdateCameraParametersFromSampleBuffer(
    CMSampleBufferRef sample_buffer, size_t width, size_t height,
    AppleCVACameraParameters *params) {
    AppleCVAMakeDefaultCameraParameters(width, height, params);
    (void)AppleCVACaptureCopyCameraIntrinsicsFromSampleBuffer(sample_buffer,
                                                              params);
}
