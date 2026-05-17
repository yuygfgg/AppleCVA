#import "app_delegate.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const uint16_t kDefaultVTSPort = 8001;

static void print_usage(const char *argv0) {
    fprintf(stderr,
            "Usage: %s [--host 127.0.0.1] [--port 8001] [--full] "
            "[--no-filter] [--no-custom] [--no-arkit-aliases] "
            "[--acva-blendshapes]\n",
            argv0);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *host = @"127.0.0.1";
        uint16_t port = kDefaultVTSPort;
        BOOL useFullBackend = NO;
        BOOL enableFilter = YES;
        BOOL includeCustomParameters = YES;
        BOOL includeARKitAliases = YES;
        BOOL includeACVABlendshapeParameters = NO;

        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
                print_usage(argv[0]);
                return 0;
            }
            if (strcmp(argv[i], "--full") == 0) {
                useFullBackend = YES;
                continue;
            }
            if (strcmp(argv[i], "--no-filter") == 0) {
                enableFilter = NO;
                continue;
            }
            if (strcmp(argv[i], "--no-custom") == 0) {
                includeCustomParameters = NO;
                continue;
            }
            if (strcmp(argv[i], "--no-arkit-aliases") == 0) {
                includeARKitAliases = NO;
                continue;
            }
            if (strcmp(argv[i], "--acva-blendshapes") == 0) {
                includeACVABlendshapeParameters = YES;
                continue;
            }
            if (strcmp(argv[i], "--host") == 0 && i + 1 < argc) {
                host = [NSString stringWithUTF8String:argv[++i]];
                continue;
            }
            if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
                const long value = strtol(argv[++i], NULL, 10);
                if (value <= 0 || value > 65535) {
                    fprintf(stderr, "Invalid VTS websocket port: %ld\n", value);
                    return 2;
                }
                port = (uint16_t)value;
                continue;
            }
            fprintf(stderr, "Unknown argument: %s\n", argv[i]);
            print_usage(argv[0]);
            return 2;
        }

        NSApplication *application = [NSApplication sharedApplication];
        VTSAppDelegate *delegate = [[VTSAppDelegate alloc]
                               initWithHost:host
                                       port:port
                             useFullBackend:useFullBackend
                               enableFilter:enableFilter
                    includeCustomParameters:includeCustomParameters
                        includeARKitAliases:includeARKitAliases
            includeACVABlendshapeParameters:includeACVABlendshapeParameters];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
