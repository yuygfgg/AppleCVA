CC := clang
BUILD_DIR := build
COMMON_WARNINGS := -Wall -Wextra
OBJC_ARC := -fobjc-arc
INCLUDES := -Iinclude
APPLECVA_FRAMEWORKS := -framework Foundation -framework Vision -framework CoreFoundation -framework CoreGraphics -framework CoreVideo -framework ImageIO

LIB_TARGET := $(BUILD_DIR)/libapplecva.dylib
IMAGE_DEMO_TARGET := $(BUILD_DIR)/image_demo
SEMANTICS_PROBE_TARGET := $(BUILD_DIR)/semantics_probe

.PHONY: all clean

all: $(LIB_TARGET) $(IMAGE_DEMO_TARGET) $(SEMANTICS_PROBE_TARGET)

$(BUILD_DIR):
	mkdir -p $@

$(LIB_TARGET): lib/applecva.m include/applecva.h | $(BUILD_DIR)
	$(CC) $(COMMON_WARNINGS) $(OBJC_ARC) $(INCLUDES) -dynamiclib lib/applecva.m $(APPLECVA_FRAMEWORKS) -o $@

$(IMAGE_DEMO_TARGET): lib/applecva.m include/applecva.h example/image_demo.m | $(BUILD_DIR)
	$(CC) $(COMMON_WARNINGS) $(OBJC_ARC) $(INCLUDES) lib/applecva.m example/image_demo.m $(APPLECVA_FRAMEWORKS) -o $@

$(SEMANTICS_PROBE_TARGET): tools/semantics_probe.m | $(BUILD_DIR)
	$(CC) $(COMMON_WARNINGS) $(OBJC_ARC) tools/semantics_probe.m -framework Foundation -framework CoreFoundation -o $@

clean:
	rm -rf $(BUILD_DIR)
