#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <stdio.h>

typedef int32_t (*CVAFaceTrackingCopySemanticsFn)(CFDictionaryRef,
                                                  CFDictionaryRef *);
typedef int32_t (*CVAFaceTrackingMaximumNumberOfTrackedFacesFn)(void);

static bool bind_symbol(void *handle, const char *name, void **out) {
    *out = dlsym(handle, name);
    if (*out == NULL) {
        fprintf(stderr, "missing symbol: %s\n", name);
        return false;
    }
    return true;
}

static void print_value_summary(NSString *indent, NSString *key, id value) {
    if ([value isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)value;
        printf("%s%s: NSArray count=%lu\n", indent.UTF8String, key.UTF8String,
               (unsigned long)array.count);
        for (NSUInteger i = 0; i < array.count; ++i) {
            id item = array[i];
            printf("%s  [%lu] %s\n", indent.UTF8String, (unsigned long)i,
                   [[item description] UTF8String]);
        }
        return;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)value;
        printf("%s%s: NSDictionary count=%lu\n", indent.UTF8String,
               key.UTF8String, (unsigned long)dictionary.count);
        for (NSString *subkey in [[dictionary allKeys]
                 sortedArrayUsingSelector:@selector(compare:)]) {
            print_value_summary([indent stringByAppendingString:@"  "], subkey,
                                dictionary[subkey]);
        }
        return;
    }
    if ([value isKindOfClass:[NSData class]]) {
        printf("%s%s: NSData length=%lu\n", indent.UTF8String, key.UTF8String,
               (unsigned long)[(NSData *)value length]);
        return;
    }
    printf("%s%s: %s\n", indent.UTF8String, key.UTF8String,
           [[value description] UTF8String]);
}

int main(void) {
    @autoreleasepool {
        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/AppleCVA.framework/AppleCVA",
            RTLD_NOW);
        if (handle == NULL) {
            fprintf(stderr, "dlopen failed: %s\n", dlerror());
            return 1;
        }

        CVAFaceTrackingCopySemanticsFn copy_semantics = NULL;
        CVAFaceTrackingMaximumNumberOfTrackedFacesFn max_tracked_faces = NULL;
        if (!bind_symbol(handle, "CVAFaceTrackingCopySemantics",
                         (void **)&copy_semantics) ||
            !bind_symbol(handle, "CVAFaceTrackingMaximumNumberOfTrackedFaces",
                         (void **)&max_tracked_faces)) {
            dlclose(handle);
            return 1;
        }

        printf("max tracked faces: %d\n", max_tracked_faces());

        CFDictionaryRef semantics = NULL;
        const int32_t status = copy_semantics(NULL, &semantics);
        printf("CVAFaceTrackingCopySemantics => %d\n", status);
        if (status != 0 || semantics == NULL) {
            dlclose(handle);
            return 1;
        }

        NSDictionary *dictionary = CFBridgingRelease(semantics);
        for (NSString *key in [[dictionary allKeys]
                 sortedArrayUsingSelector:@selector(compare:)]) {
            print_value_summary(@"", key, dictionary[key]);
        }

        dlclose(handle);
    }
    return 0;
}
