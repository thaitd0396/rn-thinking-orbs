import Metal
import QuartzCore
import UIKit

@objc(ThinkingOrbsUIView)
public final class ThinkingOrbsUIView: UIView {
    @objc public var accentColor: String = "#2A67F4" {
        didSet { colorsDirty = true; renderIfVisible() }
    }
    @objc public var dotColor: String = "#000000" {
        didSet { colorsDirty = true; renderIfVisible() }
    }
    @objc public var animated: Bool = true {
        didSet { applyPlayback() }
    }

    public override class var layerClass: AnyClass { CAMetalLayer.self }

    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let dotsBuffers: [MTLBuffer]
    private let uniformBuffers: [MTLBuffer]
    private var bufferIndex = 0
    private var displayLink: CADisplayLink?
    private var startedAt = CACurrentMediaTime()
    private var cachedFit: Float = 1
    private var cachedFitSize: Double = -1
    private var accent = SIMD4<Float>(0.1647, 0.4039, 0.9569, 1)
    private var ink = SIMD4<Float>(0, 0, 0, 1)
    private var colorsDirty = true

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    public override init(frame: CGRect) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            preconditionFailure("Metal is required for ThinkingOrbsUIView")
        }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: ThinkingOrbsShader.source, options: nil)
        } catch {
            preconditionFailure("Thinking orbs shader failed to compile: \(error)")
        }
        guard
            let prepare = library.makeFunction(name: "prepareDots"),
            let vertex = library.makeFunction(name: "vertexDot"),
            let fragment = library.makeFunction(name: "fragmentDot")
        else {
            preconditionFailure("Thinking orbs shader functions are missing")
        }
        let compute: MTLComputePipelineState
        let render: MTLRenderPipelineState
        do {
            compute = try device.makeComputePipelineState(function: prepare)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vertex
            desc.fragmentFunction = fragment
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].rgbBlendOperation = .add
            desc.colorAttachments[0].alphaBlendOperation = .add
            desc.colorAttachments[0].sourceRGBBlendFactor = .one
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            render = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            preconditionFailure("Thinking orbs pipelines failed: \(error)")
        }

        let dotsLength = MemoryLayout<ThinkingOrbsGPUDot>.stride * ThinkingOrbsGPU.dotCount
        let uniformsLength = MemoryLayout<ThinkingOrbsGPUUniforms>.stride
        var dots: [MTLBuffer] = []
        var uniforms: [MTLBuffer] = []
        for _ in 0 ..< ThinkingOrbsGPU.bufferCount {
            guard
                let dotsBuffer = device.makeBuffer(length: dotsLength, options: .storageModeShared),
                let uniformsBuffer = device.makeBuffer(length: uniformsLength, options: .storageModeShared)
            else {
                preconditionFailure("Thinking orbs GPU buffers failed")
            }
            dots.append(dotsBuffer)
            uniforms.append(uniformsBuffer)
        }

        commandQueue = queue
        computePipeline = compute
        renderPipeline = render
        dotsBuffers = dots
        uniformBuffers = uniforms

        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = UITraitCollection.current.displayScale
    }

    public required init?(coder: NSCoder) {
        nil
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            metalLayer.contentsScale = window.screen.scale
        }
        applyPlayback()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let scale = metalLayer.contentsScale
        metalLayer.drawableSize = CGSize(
            width: max(bounds.width, 0) * scale,
            height: max(bounds.height, 0) * scale
        )
        refreshFitIfNeeded()
        renderIfVisible()
    }

    deinit {
        stopAnimating()
    }

    private func renderIfVisible() {
        if window != nil {
            renderFrame()
        }
    }

    private func applyPlayback() {
        startedAt = CACurrentMediaTime()
        if window != nil, animated {
            startAnimating()
        } else {
            stopAnimating()
            if window != nil {
                renderFrame()
            }
        }
    }

    private func startAnimating() {
        if displayLink != nil { return }
        startedAt = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        } else {
            link.preferredFramesPerSecond = 60
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        renderFrame()
    }

    private func refreshFitIfNeeded() {
        let box = Double(min(bounds.width, bounds.height))
        guard box > 0, abs(box - cachedFitSize) > 0.5 else { return }
        cachedFit = Float(thinkingOrbsFit(size: box))
        cachedFitSize = box
    }

    private func renderFrame() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        refreshFitIfNeeded()
        guard let drawable = metalLayer.nextDrawable() else { return }

        if colorsDirty {
            accent = simdColor(from: accentColor)
            ink = simdColor(from: dotColor)
            colorsDirty = false
        }

        let box = Float(min(bounds.width, bounds.height))
        let seconds = animated ? CACurrentMediaTime() - startedAt : 0
        var uniforms = ThinkingOrbsGPUUniforms(
            phase: Float(thinkingOrbsPhase(period: 4.6, speed: 1, reverse: false, startAt: 0, seconds: seconds)),
            size: box,
            fit: cachedFit,
            dotScale: Float(thinkingOrbsDotScale(size: Double(box))),
            contentsScale: Float(metalLayer.contentsScale),
            pad0: 0,
            viewport: SIMD2(Float(drawable.texture.width), Float(drawable.texture.height)),
            origin: SIMD2((Float(bounds.width) - box) * 0.5, (Float(bounds.height) - box) * 0.5),
            pad1: .zero,
            accent: accent,
            ink: ink
        )

        bufferIndex = (bufferIndex + 1) % ThinkingOrbsGPU.bufferCount
        let dotsBuffer = dotsBuffers[bufferIndex]
        let uniformsBuffer = uniformBuffers[bufferIndex]
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<ThinkingOrbsGPUUniforms>.stride)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setComputePipelineState(computePipeline)
            compute.setBuffer(dotsBuffer, offset: 0, index: 0)
            compute.setBuffer(uniformsBuffer, offset: 0, index: 1)
            compute.dispatchThreadgroups(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
            )
            compute.endEncoding()
        }
        if let render = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            render.setRenderPipelineState(renderPipeline)
            render.setVertexBuffer(dotsBuffer, offset: 0, index: 0)
            render.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
            render.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: ThinkingOrbsGPU.dotCount
            )
            render.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

private enum ThinkingOrbsGPU {
    static let dotCount = 160
    static let bufferCount = 3
}

private struct ThinkingOrbsGPUDot {
    var pos: SIMD2<Float>
    var radius: Float
    var alpha: Float
    var accentAmt: Float
    var z: Float
}

private struct ThinkingOrbsGPUUniforms {
    var phase: Float
    var size: Float
    var fit: Float
    var dotScale: Float
    var contentsScale: Float
    var pad0: Float
    var viewport: SIMD2<Float>
    var origin: SIMD2<Float>
    var pad1: SIMD2<Float>
    var accent: SIMD4<Float>
    var ink: SIMD4<Float>
}

private func simdColor(from hex: String) -> SIMD4<Float> {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if value.hasPrefix("#") { value.removeFirst() }
    if value.count == 3 {
        value = value.map { "\($0)\($0)" }.joined()
    }
    if value.count == 8, let n = UInt32(value, radix: 16) {
        return SIMD4(
            Float((n >> 24) & 0xFF) / 255,
            Float((n >> 16) & 0xFF) / 255,
            Float((n >> 8) & 0xFF) / 255,
            Float(n & 0xFF) / 255
        )
    }
    guard value.count == 6, let n = UInt32(value, radix: 16) else {
        return SIMD4(0, 0, 0, 1)
    }
    return SIMD4(
        Float((n >> 16) & 0xFF) / 255,
        Float((n >> 8) & 0xFF) / 255,
        Float(n & 0xFF) / 255,
        1
    )
}
