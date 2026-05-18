#include "preview_item.h"

#import <CoreVideo/CVMetalTextureCache.h>
#import <Metal/Metal.h>

#include <QColor>
#include <QDebug>
#include <QFont>
#include <QFontMetricsF>
#include <QLineF>
#include <QMatrix4x4>
#include <QQuickWindow>
#include <QSGFlatColorMaterial>
#include <QSGGeometry>
#include <QSGMaterial>
#include <QSGNode>
#include <QSGRenderNode>
#include <QSGRendererInterface>
#include <QSGSimpleRectNode>
#include <QSGTextNode>
#include <QTextLayout>
#include <QTextOption>
#include <QtMath>

#include <cmath>
#include <cstring>
#include <limits>
#include <vector>

struct LandmarkEdge {
    uint16_t a;
    uint16_t b;
};

static const LandmarkEdge kLandmarkEdges[] = {
    {0, 2},   {2, 3},   {3, 1},   {1, 5},   {5, 4},   {4, 0},   {0, 6},
    {1, 6},   {7, 9},   {9, 10},  {10, 8},  {8, 12},  {12, 11}, {11, 7},
    {7, 13},  {8, 13},  {14, 15}, {15, 16}, {17, 18}, {18, 19}, {20, 21},
    {21, 22}, {22, 23}, {23, 24}, {24, 25}, {25, 26}, {26, 27}, {27, 28},
    {28, 29}, {29, 30}, {30, 31}, {31, 32}, {32, 33}, {33, 20}, {34, 36},
    {36, 38}, {38, 35}, {35, 39}, {39, 37}, {37, 34}, {40, 41}, {41, 42},
    {42, 43}, {44, 45}, {45, 46}, {46, 47}, {47, 48}, {49, 51}, {50, 52},
    {53, 54}, {54, 55}, {55, 56}, {56, 57}, {57, 58}, {58, 59}, {59, 65},
    {65, 64}, {64, 63}, {63, 62}, {62, 61}, {61, 60},
};

namespace {

enum class VideoTextureFormat {
    Unsupported,
    Nv12,
    Bgra,
};

struct MetalVertex {
    float position[2];
    float texCoord[2];
};

struct MetalUniforms {
    float mvp[16];
    float opacity;
    uint32_t videoRange;
    float padding[2];
};

static QSizeF pixelBufferDisplaySize(CVPixelBufferRef pixelBuffer) {
    if (pixelBuffer == nullptr) {
        return QSizeF();
    }
    if (CVPixelBufferGetPlaneCount(pixelBuffer) > 0) {
        return QSizeF(
            static_cast<qreal>(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)),
            static_cast<qreal>(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)));
    }
    return QSizeF(static_cast<qreal>(CVPixelBufferGetWidth(pixelBuffer)),
                  static_cast<qreal>(CVPixelBufferGetHeight(pixelBuffer)));
}

static VideoTextureFormat videoTextureFormat(OSType format) {
    if (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
        format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        return VideoTextureFormat::Nv12;
    }
    if (format == kCVPixelFormatType_32BGRA) {
        return VideoTextureFormat::Bgra;
    }
    return VideoTextureFormat::Unsupported;
}

static QString qStringFromNSString(NSString* string) {
    return string != nil ? QString::fromUtf8(string.UTF8String) : QString();
}

static QSGGeometryNode* createFlatGeometryNode(QSGGeometry::DrawingMode mode,
                                               const QColor& color) {
    auto* node = new QSGGeometryNode;
    auto* geometry =
        new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), 0);
    geometry->setDrawingMode(mode);
    geometry->setVertexDataPattern(QSGGeometry::DynamicPattern);

    auto* material = new QSGFlatColorMaterial;
    material->setColor(color);
    material->setFlag(QSGMaterial::Blending, color.alpha() < 255);

    node->setGeometry(geometry);
    node->setFlag(QSGNode::OwnsGeometry);
    node->setMaterial(material);
    node->setFlag(QSGNode::OwnsMaterial);
    node->setFlag(QSGNode::OwnedByParent);
    return node;
}

static void setGeometryColor(QSGGeometryNode* node, const QColor& color) {
    auto* material = static_cast<QSGFlatColorMaterial*>(node->material());
    material->setColor(color);
    material->setFlag(QSGMaterial::Blending, color.alpha() < 255);
    node->markDirty(QSGNode::DirtyMaterial);
}

static void setLineGeometry(QSGGeometryNode* node,
                            const std::vector<QLineF>& lines, float lineWidth) {
    QSGGeometry* geometry = node->geometry();
    geometry->allocate(static_cast<int>(lines.size() * 6));
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    auto* vertices = geometry->vertexDataAsPoint2D();
    int vertexIndex = 0;
    for (const QLineF& line : lines) {
        const qreal dx = line.x2() - line.x1();
        const qreal dy = line.y2() - line.y1();
        const qreal length = std::hypot(dx, dy);
        if (length <= 0.0) {
            continue;
        }

        const qreal halfWidth = static_cast<qreal>(lineWidth) * 0.5;
        const qreal nx = -dy / length * halfWidth;
        const qreal ny = dx / length * halfWidth;
        const QPointF p0(line.x1() + nx, line.y1() + ny);
        const QPointF p1(line.x2() + nx, line.y2() + ny);
        const QPointF p2(line.x1() - nx, line.y1() - ny);
        const QPointF p3(line.x2() - nx, line.y2() - ny);

        vertices[vertexIndex++].set(static_cast<float>(p0.x()),
                                    static_cast<float>(p0.y()));
        vertices[vertexIndex++].set(static_cast<float>(p1.x()),
                                    static_cast<float>(p1.y()));
        vertices[vertexIndex++].set(static_cast<float>(p2.x()),
                                    static_cast<float>(p2.y()));
        vertices[vertexIndex++].set(static_cast<float>(p2.x()),
                                    static_cast<float>(p2.y()));
        vertices[vertexIndex++].set(static_cast<float>(p1.x()),
                                    static_cast<float>(p1.y()));
        vertices[vertexIndex++].set(static_cast<float>(p3.x()),
                                    static_cast<float>(p3.y()));
    }
    geometry->setVertexCount(vertexIndex);
    geometry->markVertexDataDirty();
    node->markDirty(QSGNode::DirtyGeometry);
}

static void addRectTriangles(QSGGeometry::Point2D*& vertex,
                             const QRectF& rect) {
    const float left = static_cast<float>(rect.left());
    const float right = static_cast<float>(rect.right());
    const float top = static_cast<float>(rect.top());
    const float bottom = static_cast<float>(rect.bottom());
    vertex++->set(left, top);
    vertex++->set(right, top);
    vertex++->set(left, bottom);
    vertex++->set(left, bottom);
    vertex++->set(right, top);
    vertex++->set(right, bottom);
}

static void setPointGeometry(QSGGeometryNode* node,
                             const std::vector<QPointF>& points, qreal radius) {
    QSGGeometry* geometry = node->geometry();
    geometry->allocate(static_cast<int>(points.size() * 6));
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    auto* vertex = geometry->vertexDataAsPoint2D();
    for (const QPointF& point : points) {
        addRectTriangles(vertex, QRectF(point.x() - radius, point.y() - radius,
                                        radius * 2.0, radius * 2.0));
    }
    geometry->markVertexDataDirty();
    node->markDirty(QSGNode::DirtyGeometry);
}

static void setOutlineGeometry(QSGGeometryNode* node, const QRectF& rect,
                               qreal thickness) {
    QSGGeometry* geometry = node->geometry();
    if (rect.isEmpty()) {
        geometry->allocate(0);
        node->markDirty(QSGNode::DirtyGeometry);
        return;
    }

    geometry->allocate(24);
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    auto* vertex = geometry->vertexDataAsPoint2D();
    const qreal half = thickness * 0.5;
    addRectTriangles(vertex, QRectF(rect.left() - half, rect.top() - half,
                                    rect.width() + thickness, thickness));
    addRectTriangles(vertex, QRectF(rect.left() - half, rect.bottom() - half,
                                    rect.width() + thickness, thickness));
    addRectTriangles(vertex, QRectF(rect.left() - half, rect.top() - half,
                                    thickness, rect.height() + thickness));
    addRectTriangles(vertex, QRectF(rect.right() - half, rect.top() - half,
                                    thickness, rect.height() + thickness));
    geometry->markVertexDataDirty();
    node->markDirty(QSGNode::DirtyGeometry);
}

static void updateTextNode(QSGTextNode* node, const QString& text,
                           const QFont& font, const QRectF& textRect) {
    if (node == nullptr) {
        return;
    }
    QTextLayout layout(text, font);
    QTextOption option;
    option.setWrapMode(QTextOption::WordWrap);
    layout.setTextOption(option);
    layout.beginLayout();
    qreal y = 0.0;
    while (true) {
        QTextLine line = layout.createLine();
        if (!line.isValid()) {
            break;
        }
        line.setLineWidth(textRect.width());
        line.setPosition(QPointF(0.0, y));
        y += line.height();
    }
    layout.endLayout();

    node->clear();
    node->setColor(QColor(255, 255, 255));
    node->setRenderType(QSGTextNode::QtRendering);
    node->setFiltering(QSGTexture::Linear);
    node->addTextLayout(textRect.topLeft(), &layout);
}

class VTSMetalVideoNode final : public QSGRenderNode {
  public:
    ~VTSMetalVideoNode() override {
        clearPixelBuffer();
        releaseMetalResources();
    }

    void setFrame(QQuickWindow* window, CVPixelBufferRef pixelBuffer,
                  const QRectF& targetRect, OSType pixelFormat, bool mirror,
                  bool showCameraPreview) {
        window_ = window;
        targetRect_ = targetRect;
        pixelFormat_ = pixelFormat;
        mirror_ = mirror;
        showCameraPreview_ = showCameraPreview;
        replacePixelBuffer(pixelBuffer);
    }

    void render(const RenderState* state) override {
        if (!showCameraPreview_ || pixelBuffer_ == nullptr ||
            targetRect_.isEmpty()) {
            return;
        }

        const VideoTextureFormat format = videoTextureFormat(pixelFormat_);
        if (format == VideoTextureFormat::Unsupported) {
            return;
        }

        if (window_ != nullptr) {
            window_->beginExternalCommands();
        }

        id<MTLDevice> device = nil;
        id<MTLRenderCommandEncoder> encoder = nil;
        if (!ensureMetalResources(&device, &encoder)) {
            if (window_ != nullptr) {
                window_->endExternalCommands();
            }
            return;
        }
        id<MTLRenderPipelineState> pipeline = ensurePipeline(device, format);
        if (pipeline == nil) {
            window_->endExternalCommands();
            return;
        }

        CVMetalTextureRef yTextureRef = nullptr;
        CVMetalTextureRef uvTextureRef = nullptr;
        CVMetalTextureRef colorTextureRef = nullptr;
        id<MTLTexture> yTexture = nil;
        id<MTLTexture> uvTexture = nil;
        id<MTLTexture> colorTexture = nil;

        if (format == VideoTextureFormat::Nv12) {
            const size_t yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer_, 0);
            const size_t yHeight =
                CVPixelBufferGetHeightOfPlane(pixelBuffer_, 0);
            const size_t uvWidth =
                CVPixelBufferGetWidthOfPlane(pixelBuffer_, 1);
            const size_t uvHeight =
                CVPixelBufferGetHeightOfPlane(pixelBuffer_, 1);
            if (CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault, textureCache_, pixelBuffer_, nullptr,
                    MTLPixelFormatR8Unorm, yWidth, yHeight, 0,
                    &yTextureRef) != kCVReturnSuccess ||
                CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault, textureCache_, pixelBuffer_, nullptr,
                    MTLPixelFormatRG8Unorm, uvWidth, uvHeight, 1,
                    &uvTextureRef) != kCVReturnSuccess) {
                if (yTextureRef != nullptr) {
                    CFRelease(yTextureRef);
                }
                if (uvTextureRef != nullptr) {
                    CFRelease(uvTextureRef);
                }
                window_->endExternalCommands();
                return;
            }
            yTexture = CVMetalTextureGetTexture(yTextureRef);
            uvTexture = CVMetalTextureGetTexture(uvTextureRef);
            if (yTexture == nil || uvTexture == nil) {
                CFRelease(yTextureRef);
                CFRelease(uvTextureRef);
                window_->endExternalCommands();
                return;
            }
        } else {
            const size_t width = CVPixelBufferGetWidth(pixelBuffer_);
            const size_t height = CVPixelBufferGetHeight(pixelBuffer_);
            if (CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault, textureCache_, pixelBuffer_, nullptr,
                    MTLPixelFormatBGRA8Unorm, width, height, 0,
                    &colorTextureRef) != kCVReturnSuccess) {
                window_->endExternalCommands();
                return;
            }
            colorTexture = CVMetalTextureGetTexture(colorTextureRef);
            if (colorTexture == nil) {
                CFRelease(colorTextureRef);
                window_->endExternalCommands();
                return;
            }
        }

        const float tx0 = mirror_ ? 1.0f : 0.0f;
        const float tx1 = mirror_ ? 0.0f : 1.0f;
        MetalVertex vertices[4] = {
            {{static_cast<float>(targetRect_.left()),
              static_cast<float>(targetRect_.top())},
             {tx0, 0.0f}},
            {{static_cast<float>(targetRect_.right()),
              static_cast<float>(targetRect_.top())},
             {tx1, 0.0f}},
            {{static_cast<float>(targetRect_.left()),
              static_cast<float>(targetRect_.bottom())},
             {tx0, 1.0f}},
            {{static_cast<float>(targetRect_.right()),
              static_cast<float>(targetRect_.bottom())},
             {tx1, 1.0f}},
        };

        QMatrix4x4 mvp;
        if (state != nullptr && state->projectionMatrix() != nullptr) {
            mvp = *state->projectionMatrix();
        }
        if (matrix() != nullptr) {
            mvp *= *matrix();
        }

        MetalUniforms uniforms = {};
        std::memcpy(uniforms.mvp, mvp.constData(), sizeof(uniforms.mvp));
        uniforms.opacity = static_cast<float>(inheritedOpacity());
        uniforms.videoRange =
            pixelFormat_ == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                ? 1u
                : 0u;

        [encoder setRenderPipelineState:pipeline];
        [encoder setDepthStencilState:depthStencilState_];
        [encoder setCullMode:MTLCullModeNone];
        [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
        [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        [encoder setFragmentSamplerState:sampler_ atIndex:0];
        if (format == VideoTextureFormat::Nv12) {
            [encoder setFragmentTexture:yTexture atIndex:0];
            [encoder setFragmentTexture:uvTexture atIndex:1];
        } else {
            [encoder setFragmentTexture:colorTexture atIndex:0];
        }
        [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                    vertexStart:0
                    vertexCount:4];
        window_->endExternalCommands();

        if (yTextureRef != nullptr) {
            CFRelease(yTextureRef);
        }
        if (uvTextureRef != nullptr) {
            CFRelease(uvTextureRef);
        }
        if (colorTextureRef != nullptr) {
            CFRelease(colorTextureRef);
        }
    }

    void releaseResources() override {
        clearPixelBuffer();
        releaseMetalResources();
    }

    StateFlags changedStates() const override {
        return DepthState | StencilState | ScissorState | ColorState |
               BlendState | CullState | ViewportState;
    }

    RenderingFlags flags() const override { return BoundedRectRendering; }

    QRectF rect() const override { return targetRect_; }

  private:
    void replacePixelBuffer(CVPixelBufferRef pixelBuffer) {
        if (pixelBuffer != nullptr) {
            CVPixelBufferRetain(pixelBuffer);
        }
        clearPixelBuffer();
        pixelBuffer_ = pixelBuffer;
    }

    void clearPixelBuffer() {
        if (pixelBuffer_ != nullptr) {
            CVPixelBufferRelease(pixelBuffer_);
            pixelBuffer_ = nullptr;
        }
    }

    void releaseMetalResources() {
        if (textureCache_ != nullptr) {
            CFRelease(textureCache_);
            textureCache_ = nullptr;
        }
        deviceKey_ = nullptr;
        sampler_ = nil;
        depthStencilState_ = nil;
        nv12Pipeline_ = nil;
        bgraPipeline_ = nil;
    }

    bool ensureMetalResources(id<MTLDevice>* outDevice,
                              id<MTLRenderCommandEncoder>* outEncoder) {
        if (window_ == nullptr) {
            return false;
        }
        QSGRendererInterface* rendererInterface = window_->rendererInterface();
        if (rendererInterface == nullptr ||
            rendererInterface->graphicsApi() != QSGRendererInterface::Metal) {
            return false;
        }

        void* deviceResource = rendererInterface->getResource(
            window_, QSGRendererInterface::DeviceResource);
        void* encoderResource = rendererInterface->getResource(
            window_, QSGRendererInterface::CommandEncoderResource);
        if (deviceResource == nullptr || encoderResource == nullptr) {
            return false;
        }

        id<MTLDevice> device = (__bridge id<MTLDevice>)deviceResource;
        id<MTLRenderCommandEncoder> encoder =
            (__bridge id<MTLRenderCommandEncoder>)encoderResource;
        if (device == nil || encoder == nil) {
            return false;
        }

        if (deviceResource != deviceKey_) {
            releaseMetalResources();
            deviceKey_ = deviceResource;
            if (CVMetalTextureCacheCreate(kCFAllocatorDefault, nullptr, device,
                                          nullptr,
                                          &textureCache_) != kCVReturnSuccess) {
                releaseMetalResources();
                return false;
            }

            MTLSamplerDescriptor* samplerDescriptor =
                [[MTLSamplerDescriptor alloc] init];
            samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
            samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
            samplerDescriptor.mipFilter = MTLSamplerMipFilterNotMipmapped;
            samplerDescriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
            samplerDescriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
            sampler_ = [device newSamplerStateWithDescriptor:samplerDescriptor];
            if (sampler_ == nil) {
                releaseMetalResources();
                return false;
            }

            MTLDepthStencilDescriptor* depthDescriptor =
                [[MTLDepthStencilDescriptor alloc] init];
            depthDescriptor.depthCompareFunction = MTLCompareFunctionAlways;
            depthDescriptor.depthWriteEnabled = NO;
            depthStencilState_ =
                [device newDepthStencilStateWithDescriptor:depthDescriptor];
            if (depthStencilState_ == nil) {
                releaseMetalResources();
                return false;
            }
        }

        *outDevice = device;
        *outEncoder = encoder;
        return textureCache_ != nullptr;
    }

    id<MTLRenderPipelineState> ensurePipeline(id<MTLDevice> device,
                                              VideoTextureFormat format) {
        __strong id<MTLRenderPipelineState>* pipelineSlot =
            format == VideoTextureFormat::Nv12 ? &nv12Pipeline_
                                               : &bgraPipeline_;
        if (*pipelineSlot != nil) {
            return *pipelineSlot;
        }

        static const char* kMetalShaderSource = R"metal(
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position;
    float2 texCoord;
};

struct Uniforms {
    float4x4 mvp;
    float opacity;
    uint videoRange;
    float2 padding;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vtsVertex(uint vertexID [[vertex_id]],
                           constant VertexIn* vertices [[buffer(0)]],
                           constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.mvp * float4(vertices[vertexID].position, 0.0, 1.0);
    out.texCoord = vertices[vertexID].texCoord;
    return out;
}

fragment float4 vtsNv12Fragment(VertexOut in [[stage_in]],
                                texture2d<float> yTexture [[texture(0)]],
                                texture2d<float> uvTexture [[texture(1)]],
                                sampler textureSampler [[sampler(0)]],
                                constant Uniforms& uniforms [[buffer(1)]]) {
    float y = yTexture.sample(textureSampler, in.texCoord).r;
    if (uniforms.videoRange != 0) {
        y = max(0.0, (y - (16.0 / 255.0)) * (255.0 / 219.0));
    }
    float2 uv = uvTexture.sample(textureSampler, in.texCoord).rg - float2(0.5, 0.5);
    float3 rgb;
    rgb.r = y + 1.402 * uv.y;
    rgb.g = y - 0.344136 * uv.x - 0.714136 * uv.y;
    rgb.b = y + 1.772 * uv.x;
    return float4(clamp(rgb, 0.0, 1.0), uniforms.opacity);
}

fragment float4 vtsBgraFragment(VertexOut in [[stage_in]],
                                texture2d<float> colorTexture [[texture(0)]],
                                sampler textureSampler [[sampler(0)]],
                                constant Uniforms& uniforms [[buffer(1)]]) {
    float4 color = colorTexture.sample(textureSampler, in.texCoord);
    color.a *= uniforms.opacity;
    return color;
}
)metal";

        NSString* shaderSource =
            [NSString stringWithUTF8String:kMetalShaderSource];
        NSError* error = nil;
        id<MTLLibrary> library =
            [device newLibraryWithSource:shaderSource options:nil error:&error];
        if (library == nil) {
            qWarning() << "Failed to compile VTS Metal preview shader:"
                       << qStringFromNSString(error.localizedDescription);
            return nil;
        }

        id<MTLFunction> vertexFunction =
            [library newFunctionWithName:@"vtsVertex"];
        id<MTLFunction> fragmentFunction =
            [library newFunctionWithName:format == VideoTextureFormat::Nv12
                                             ? @"vtsNv12Fragment"
                                             : @"vtsBgraFragment"];
        if (vertexFunction == nil || fragmentFunction == nil) {
            qWarning() << "Failed to load VTS Metal preview shader functions.";
            return nil;
        }

        MTLRenderPipelineDescriptor* descriptor =
            [[MTLRenderPipelineDescriptor alloc] init];
        descriptor.vertexFunction = vertexFunction;
        descriptor.fragmentFunction = fragmentFunction;
        descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        descriptor.colorAttachments[0].blendingEnabled = YES;
        descriptor.colorAttachments[0].sourceRGBBlendFactor =
            MTLBlendFactorSourceAlpha;
        descriptor.colorAttachments[0].destinationRGBBlendFactor =
            MTLBlendFactorOneMinusSourceAlpha;
        descriptor.colorAttachments[0].sourceAlphaBlendFactor =
            MTLBlendFactorOne;
        descriptor.colorAttachments[0].destinationAlphaBlendFactor =
            MTLBlendFactorOneMinusSourceAlpha;

        *pipelineSlot = [device newRenderPipelineStateWithDescriptor:descriptor
                                                               error:&error];
        if (*pipelineSlot == nil) {
            qWarning() << "Failed to create VTS Metal preview pipeline:"
                       << qStringFromNSString(error.localizedDescription);
        }
        return *pipelineSlot;
    }

    QQuickWindow* window_ = nullptr;
    CVPixelBufferRef pixelBuffer_ = nullptr;
    QRectF targetRect_;
    OSType pixelFormat_ = 0;
    bool mirror_ = true;
    bool showCameraPreview_ = true;

    void* deviceKey_ = nullptr;
    CVMetalTextureCacheRef textureCache_ = nullptr;
    __strong id<MTLSamplerState> sampler_ = nil;
    __strong id<MTLDepthStencilState> depthStencilState_ = nil;
    __strong id<MTLRenderPipelineState> nv12Pipeline_ = nil;
    __strong id<MTLRenderPipelineState> bgraPipeline_ = nil;
};

} // namespace

class VTSPreviewRootNode final : public QSGNode {
  public:
    explicit VTSPreviewRootNode(QQuickWindow* window) {
        background_ = new QSGSimpleRectNode;
        background_->setFlag(QSGNode::OwnedByParent);
        appendChildNode(background_);

        video_ = new VTSMetalVideoNode;
        video_->setFlag(QSGNode::OwnedByParent);
        appendChildNode(video_);

        faceOutline_ = createFlatGeometryNode(QSGGeometry::DrawTriangles,
                                              QColor(255, 184, 46, 230));
        appendChildNode(faceOutline_);

        landmarkLines_ = createFlatGeometryNode(QSGGeometry::DrawLines,
                                                QColor(26, 255, 140, 230));
        appendChildNode(landmarkLines_);

        landmarkPoints_ = createFlatGeometryNode(QSGGeometry::DrawTriangles,
                                                 QColor(140, 230, 255, 245));
        appendChildNode(landmarkPoints_);

        statusBox_ = new QSGSimpleRectNode;
        statusBox_->setFlag(QSGNode::OwnedByParent);
        appendChildNode(statusBox_);

        ensureTextNode(window);
    }

    void sync(VTSPreviewItem* item) {
        const QRectF bounds = item->boundingRect();
        background_->setRect(bounds);
        background_->setColor(QColor(12, 12, 16));

        const bool hasFrame =
            item->sourceSize_.width() > 0.0 && item->sourceSize_.height() > 0.0;
        const QRectF imageRect =
            hasFrame ? item->aspectFitRect(item->sourceSize_, bounds) : bounds;

        video_->setFrame(item->window(), item->pixelBuffer_, imageRect,
                         item->pixelFormat_, item->mirrorPreview_,
                         item->showCameraPreview_ && hasFrame);

        syncFaceOverlay(item, imageRect, hasFrame);
        syncStatusOverlay(item);
    }

  private:
    void ensureTextNode(QQuickWindow* window) {
        if (statusText_ != nullptr || window == nullptr) {
            return;
        }
        statusText_ = window->createTextNode();
        if (statusText_ != nullptr) {
            statusText_->setFlag(QSGNode::OwnedByParent);
            appendChildNode(statusText_);
        }
    }

    void syncFaceOverlay(VTSPreviewItem* item, const QRectF& imageRect,
                         bool hasFrame) {
        if (!hasFrame || !item->hasFace_) {
            setOutlineGeometry(faceOutline_, QRectF(), 0.0);
            setLineGeometry(landmarkLines_, {}, 1.0f);
            setPointGeometry(landmarkPoints_, {}, 0.0);
            return;
        }

        const size_t imageWidth =
            static_cast<size_t>(item->sourceSize_.width());
        const size_t imageHeight =
            static_cast<size_t>(item->sourceSize_.height());

        QRectF landmarkBounds;
        const bool hasLandmarkBounds = item->landmarkBoundsForFace(
            item->face_, imageRect, imageWidth, imageHeight, &landmarkBounds);

        QRectF faceBounds;
        if (item->face_.rect[2] > 0.0f && item->face_.rect[3] > 0.0f) {
            faceBounds =
                item->rectForNormalizedFaceRect(item->face_.rect, imageRect);
        } else if (hasLandmarkBounds) {
            faceBounds = landmarkBounds;
        }
        setOutlineGeometry(faceOutline_, faceBounds, 2.0);
        setGeometryColor(faceOutline_, QColor(255, 184, 46, 230));

        std::vector<QLineF> lines;
        lines.reserve(sizeof(kLandmarkEdges) / sizeof(kLandmarkEdges[0]));
        for (const LandmarkEdge& edge : kLandmarkEdges) {
            if (edge.a >= item->face_.landmark_pair_count ||
                edge.b >= item->face_.landmark_pair_count) {
                continue;
            }
            const size_t aBase = static_cast<size_t>(edge.a) * 2;
            const size_t bBase = static_cast<size_t>(edge.b) * 2;
            if (aBase + 1 >= item->face_.landmark_float_count ||
                bBase + 1 >= item->face_.landmark_float_count) {
                continue;
            }
            const QPointF a = item->landmarkPoint(
                item->face_.landmarks[aBase], item->face_.landmarks[aBase + 1],
                imageRect, imageWidth, imageHeight, landmarkBounds,
                hasLandmarkBounds);
            const QPointF b = item->landmarkPoint(
                item->face_.landmarks[bBase], item->face_.landmarks[bBase + 1],
                imageRect, imageWidth, imageHeight, landmarkBounds,
                hasLandmarkBounds);
            lines.emplace_back(a, b);
        }
        setLineGeometry(landmarkLines_, lines, 1.6f);
        setGeometryColor(landmarkLines_, QColor(26, 255, 140, 230));

        std::vector<QPointF> points;
        points.reserve(item->face_.landmark_pair_count);
        for (size_t i = 0; i < item->face_.landmark_pair_count; ++i) {
            const size_t base = i * 2;
            if (base + 1 >= item->face_.landmark_float_count) {
                continue;
            }
            points.push_back(item->landmarkPoint(
                item->face_.landmarks[base], item->face_.landmarks[base + 1],
                imageRect, imageWidth, imageHeight, landmarkBounds,
                hasLandmarkBounds));
        }
        setPointGeometry(landmarkPoints_, points, 2.4);
        setGeometryColor(landmarkPoints_, QColor(140, 230, 255, 245));
    }

    void syncStatusOverlay(VTSPreviewItem* item) {
        ensureTextNode(item->window());

        QString text = QStringLiteral("%1 FPS  detected %2  tracked %3")
                           .arg(item->fps_, 0, 'f', 1)
                           .arg(item->detectedFaceCount_)
                           .arg(item->trackedFaceCount_);
        if (item->hasFace_) {
            text += QStringLiteral("  confidence %1")
                        .arg(item->face_.confidence, 0, 'f', 3);
        }
        if (item->lastStatus_ != APPLECVA_OK) {
            text += QStringLiteral("\nstatus %1 (%2)")
                        .arg(QString::fromUtf8(
                            AppleCVAStatusString(item->lastStatus_)))
                        .arg(item->lastStatus_);
        }

        QFont font;
        font.setFamily(QStringLiteral("Menlo"));
        font.setPointSizeF(12.0);

        const qreal maxTextWidth = qMax<qreal>(0.0, item->width() - 32.0);
        const QFontMetricsF metrics(font);
        const QRectF measuredTextRect = metrics.boundingRect(
            QRectF(0.0, 0.0, maxTextWidth, item->height()),
            Qt::AlignLeft | Qt::AlignTop | Qt::TextWordWrap, text);
        const QRectF box(14.0, 14.0,
                         qMin(measuredTextRect.width() + 18.0,
                              qMax<qreal>(0.0, item->width() - 28.0)),
                         measuredTextRect.height() + 12.0);
        statusBox_->setRect(box);
        statusBox_->setColor(QColor(0, 0, 0, 150));

        updateTextNode(statusText_, text, font,
                       box.adjusted(9.0, 6.0, -9.0, -6.0));
    }

    QSGSimpleRectNode* background_ = nullptr;
    VTSMetalVideoNode* video_ = nullptr;
    QSGGeometryNode* faceOutline_ = nullptr;
    QSGGeometryNode* landmarkLines_ = nullptr;
    QSGGeometryNode* landmarkPoints_ = nullptr;
    QSGSimpleRectNode* statusBox_ = nullptr;
    QSGTextNode* statusText_ = nullptr;
};

VTSPreviewItem::VTSPreviewItem(QQuickItem* parent) : QQuickItem(parent) {
    setFlag(ItemHasContents, true);
}

VTSPreviewItem::~VTSPreviewItem() { clearPixelBuffer(); }

bool VTSPreviewItem::mirrorPreview() const { return mirrorPreview_; }

void VTSPreviewItem::setMirrorPreview(bool enabled) {
    if (mirrorPreview_ == enabled) {
        return;
    }
    mirrorPreview_ = enabled;
    update();
    emit mirrorPreviewChanged();
}

bool VTSPreviewItem::showCameraPreview() const { return showCameraPreview_; }

void VTSPreviewItem::setShowCameraPreview(bool enabled) {
    if (showCameraPreview_ == enabled) {
        return;
    }
    showCameraPreview_ = enabled;
    update();
    emit showCameraPreviewChanged();
}

bool VTSPreviewItem::flipLandmarkY() const { return flipLandmarkY_; }

void VTSPreviewItem::setFlipLandmarkY(bool enabled) {
    if (flipLandmarkY_ == enabled) {
        return;
    }
    flipLandmarkY_ = enabled;
    update();
    emit flipLandmarkYChanged();
}

bool VTSPreviewItem::topLeftOrigin() const { return topLeftOrigin_; }

void VTSPreviewItem::setTopLeftOrigin(bool enabled) {
    if (topLeftOrigin_ == enabled) {
        return;
    }
    topLeftOrigin_ = enabled;
    update();
    emit topLeftOriginChanged();
}

void VTSPreviewItem::setFrame(CVPixelBufferRef pixelBuffer,
                              const AppleCVATrackedFace* face, bool hasFace,
                              size_t detectedFaceCount, size_t trackedFaceCount,
                              int32_t lastStatus, double fps) {
    if (pixelBuffer != nullptr) {
        CVPixelBufferRetain(pixelBuffer);
    }
    clearPixelBuffer();
    pixelBuffer_ = pixelBuffer;
    sourceSize_ = pixelBufferDisplaySize(pixelBuffer_);
    pixelFormat_ = pixelBuffer_ != nullptr
                       ? CVPixelBufferGetPixelFormatType(pixelBuffer_)
                       : 0;

    std::memset(&face_, 0, sizeof(face_));
    if (face != nullptr) {
        face_ = *face;
    }
    hasFace_ = hasFace;
    detectedFaceCount_ = detectedFaceCount;
    trackedFaceCount_ = trackedFaceCount;
    lastStatus_ = lastStatus;
    fps_ = fps;
    update();
}

QSGNode*
VTSPreviewItem::updatePaintNode(QSGNode* oldNode,
                                UpdatePaintNodeData* updatePaintNodeData) {
    (void)updatePaintNodeData;
    auto* root = static_cast<VTSPreviewRootNode*>(oldNode);
    if (root == nullptr) {
        root = new VTSPreviewRootNode(window());
    }
    root->sync(this);
    return root;
}

QRectF VTSPreviewItem::aspectFitRect(const QSizeF& sourceSize,
                                     const QRectF& bounds) const {
    if (sourceSize.width() <= 0.0 || sourceSize.height() <= 0.0 ||
        bounds.width() <= 0.0 || bounds.height() <= 0.0) {
        return bounds;
    }
    const qreal sourceAspect = sourceSize.width() / sourceSize.height();
    const qreal boundsAspect = bounds.width() / bounds.height();
    QRectF rect = bounds;
    if (boundsAspect > sourceAspect) {
        rect.setWidth(bounds.height() * sourceAspect);
        rect.moveLeft(bounds.left() + (bounds.width() - rect.width()) * 0.5);
    } else {
        rect.setHeight(bounds.width() / sourceAspect);
        rect.moveTop(bounds.top() + (bounds.height() - rect.height()) * 0.5);
    }
    return rect;
}

QPointF VTSPreviewItem::pointForImagePoint(float x, float y, size_t imageWidth,
                                           size_t imageHeight,
                                           const QRectF& imageRect) const {
    if (!topLeftOrigin_) {
        y = static_cast<float>(imageHeight) - y;
    }
    if (mirrorPreview_) {
        x = static_cast<float>(imageWidth) - x;
    }
    const qreal scaleX = imageRect.width() / static_cast<qreal>(imageWidth);
    const qreal scaleY = imageRect.height() / static_cast<qreal>(imageHeight);
    return QPointF(imageRect.left() + static_cast<qreal>(x) * scaleX,
                   imageRect.top() + static_cast<qreal>(y) * scaleY);
}

QRectF
VTSPreviewItem::rectForNormalizedFaceRect(const float rect[4],
                                          const QRectF& imageRect) const {
    qreal sourceX = static_cast<qreal>(rect[0]);
    qreal sourceY = static_cast<qreal>(rect[1]);
    if (!topLeftOrigin_) {
        sourceY = 1.0 - sourceY - static_cast<qreal>(rect[3]);
    }
    if (mirrorPreview_) {
        sourceX = 1.0 - sourceX - static_cast<qreal>(rect[2]);
    }
    return QRectF(imageRect.left() + sourceX * imageRect.width(),
                  imageRect.top() + sourceY * imageRect.height(),
                  static_cast<qreal>(rect[2]) * imageRect.width(),
                  static_cast<qreal>(rect[3]) * imageRect.height());
}

bool VTSPreviewItem::landmarkBoundsForFace(const AppleCVATrackedFace& face,
                                           const QRectF& imageRect,
                                           size_t imageWidth,
                                           size_t imageHeight,
                                           QRectF* outRect) const {
    if (outRect == nullptr || face.landmark_pair_count == 0) {
        return false;
    }

    qreal minX = std::numeric_limits<qreal>::max();
    qreal minY = std::numeric_limits<qreal>::max();
    qreal maxX = -std::numeric_limits<qreal>::max();
    qreal maxY = -std::numeric_limits<qreal>::max();
    size_t validCount = 0;
    for (size_t i = 0; i < face.landmark_pair_count; ++i) {
        const size_t base = i * 2;
        if (base + 1 >= face.landmark_float_count ||
            base + 1 >= APPLECVA_MAX_LANDMARK_FLOATS) {
            continue;
        }
        const float x = face.landmarks[base];
        const float y = face.landmarks[base + 1];
        if (!std::isfinite(x) || !std::isfinite(y)) {
            continue;
        }
        const QPointF point =
            pointForImagePoint(x, y, imageWidth, imageHeight, imageRect);
        minX = qMin(minX, point.x());
        minY = qMin(minY, point.y());
        maxX = qMax(maxX, point.x());
        maxY = qMax(maxY, point.y());
        ++validCount;
    }

    if (validCount < 6 || maxX <= minX || maxY <= minY) {
        return false;
    }

    const qreal padX = qMax(18.0, (maxX - minX) * 0.16);
    const qreal padY = qMax(18.0, (maxY - minY) * 0.22);
    minX = qMax(imageRect.left(), minX - padX);
    minY = qMax(imageRect.top(), minY - padY);
    maxX = qMin(imageRect.right(), maxX + padX);
    maxY = qMin(imageRect.bottom(), maxY + padY);
    *outRect = QRectF(QPointF(minX, minY), QPointF(maxX, maxY));
    return true;
}

QPointF VTSPreviewItem::landmarkPoint(float x, float y, const QRectF& imageRect,
                                      size_t imageWidth, size_t imageHeight,
                                      const QRectF& landmarkBounds,
                                      bool hasLandmarkBounds) const {
    QPointF point =
        pointForImagePoint(x, y, imageWidth, imageHeight, imageRect);
    if (flipLandmarkY_ && hasLandmarkBounds) {
        point.setY(landmarkBounds.top() + landmarkBounds.bottom() - point.y());
    }
    return point;
}

void VTSPreviewItem::clearPixelBuffer() {
    if (pixelBuffer_ != nullptr) {
        CVPixelBufferRelease(pixelBuffer_);
        pixelBuffer_ = nullptr;
    }
}
