#ifndef VTS_SOURCE_APP_DELEGATE_H
#define VTS_SOURCE_APP_DELEGATE_H

#import <AppKit/AppKit.h>

@interface VTSAppDelegate : NSObject <NSApplicationDelegate>

- (instancetype)initWithHost:(NSString *)host
                               port:(uint16_t)port
                     useFullBackend:(BOOL)useFullBackend
                       enableFilter:(BOOL)enableFilter
            includeCustomParameters:(BOOL)includeCustomParameters
                includeARKitAliases:(BOOL)includeARKitAliases
    includeACVABlendshapeParameters:(BOOL)includeACVABlendshapeParameters;

@end

#endif
