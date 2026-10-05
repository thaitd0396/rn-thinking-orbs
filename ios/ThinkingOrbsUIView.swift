import Metal
import QuartzCore
import simd
import UIKit

@objc(ThinkingOrbsUIView)
public final class ThinkingOrbsUIView: UIView, UIGestureRecognizerDelegate {
    @objc public var accentColor: String = "#2A67F4" {
        didSet { updateColors() }
    }
    @objc public var dotColor: String = "#000000" {
        didSet { updateColors() }
    }
    @objc public var animated: Bool = true {
        didSet { updatePlayback() }
    }
    @objc public var interactive: Bool = false {
        didSet { applyInteraction() }
    }

    public override class var layerClass: AnyClass { CAMetalLayer.self }

    private var renderer: ThinkingOrbsRenderer!
    private let grabRecognizer = ThinkingOrbsGrabRecognizer()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        renderer = ThinkingOrbsRenderer(layer: layer as! CAMetalLayer)
        grabRecognizer.addTarget(self, action: #selector(handleGrab))
        grabRecognizer.delegate = self
        grabRecognizer.cancelsTouchesInView = true
        addGestureRecognizer(grabRecognizer)
        NotificationCenter.default.addObserver(
            self, selector: #selector(updatePlayback),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(updatePlayback),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        applyInteraction()
    }

    public required init?(coder: NSCoder) {
        nil
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateLayout()
        updatePlayback()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        renderer.shutdown()
    }

    private func updateLayout() {
        let size = bounds.size
        let scale = window?.screen.scale ?? traitCollection.displayScale
        let fps = min(window?.screen.maximumFramesPerSecond ?? 60, 120)
        let metalLayer = layer as! CAMetalLayer
        if metalLayer.contentsScale != scale {
            metalLayer.contentsScale = scale
        }
        let drawableSize = CGSize(width: max(size.width, 0) * scale, height: max(size.height, 0) * scale)
        if metalLayer.drawableSize != drawableSize {
            metalLayer.drawableSize = drawableSize
        }
        renderer.enqueue { $0.updateLayout(size: size, scale: scale, fps: fps) }
    }

    private func updateColors() {
        let accent = accentColor
        let ink = dotColor
        renderer.enqueue { $0.updateColors(accent: accent, ink: ink) }
    }

    @objc private func updatePlayback(_ notification: Notification? = nil) {
        let active = notification?.name != UIApplication.willResignActiveNotification
            && UIApplication.shared.applicationState == .active
        let visible = window != nil && active
        let animated = animated
        let interactive = interactive
        renderer.enqueue { $0.updatePlayback(visible: visible, animated: animated, interactive: interactive) }
    }

    private func applyInteraction() {
        isUserInteractionEnabled = interactive
        grabRecognizer.isEnabled = interactive
        updatePlayback()
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === grabRecognizer
    }

    @objc private func handleGrab(_ recognizer: UIGestureRecognizer) {
        let point = recognizer.location(in: self)
        let time = CACurrentMediaTime()
        switch recognizer.state {
        case .began:
            renderer.enqueue { $0.grab(at: point, atTime: time) }
        case .changed:
            renderer.enqueue { $0.roll(to: point, atTime: time) }
        case .ended, .cancelled:
            renderer.enqueue { $0.releaseGrab() }
        default:
            break
        }
    }
}

private final class ThinkingOrbsRenderer {
    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let dotsBuffers: [MTLBuffer]
    private let uniformBuffers: [MTLBuffer]
    private var bufferIndex = 0
    private let renderQueue = DispatchQueue(label: "com.rnthinkingorbs.render", qos: .userInteractive)
    private let inFlightFrames = DispatchSemaphore(value: ThinkingOrbsGPU.bufferCount)
    private var timer: DispatchSourceTimer?
    private let metalLayer: CAMetalLayer
    private var bounds: CGRect = .zero
    private var contentsScale: CGFloat = 1
    private var visible = false
    private var framesPerSecond = 60
    private var animated = true
    private var interactive = false
    private var cachedFit: Float = 1
    private var cachedFitSize: Double = -1
    private var accent = SIMD4<Float>(0.1647, 0.4039, 0.9569, 1)
    private var ink = SIMD4<Float>(0, 0, 0, 1)

    private var userRotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    /// View-space spin in the same units as `rollSurface` (radians / view-width per second).
    /// Axis is always parallel to the screen: ω = (-vy, vx, 0).
    private var velocityX: Float = -ThinkingOrbsSpin.idleSpeed
    private var velocityY: Float = 0
    private var idleDirX: Float = -1
    private var idleDirY: Float = 0
    private var lastTouchPoint: CGPoint = .zero
    private var lastTouchAt = CACurrentMediaTime()
    private var lastTickAt = CACurrentMediaTime()
    private var idleSeconds: CFTimeInterval = 0
    private var idleRunningSince: CFTimeInterval?
    private var touching = false

    init(layer: CAMetalLayer) {
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

        metalLayer = layer
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
    }

    func enqueue(_ update: @escaping (ThinkingOrbsRenderer) -> Void) {
        renderQueue.async { [self] in
            autoreleasepool { update(self) }
        }
    }

    func shutdown() {
        enqueue {
            $0.visible = false
            $0.freezeIdle()
            $0.stopAnimating()
        }
    }

    func updateLayout(size: CGSize, scale: CGFloat, fps: Int) {
        if bounds.size != size || contentsScale != scale {
            bounds.size = size
            contentsScale = scale
            refreshFitIfNeeded()
        }
        if framesPerSecond != fps {
            framesPerSecond = max(fps, 1)
            stopAnimating()
            applyPlayback()
        }
        renderIfVisible()
    }

    func updateColors(accent: String, ink: String) {
        self.accent = simdColor(from: accent)
        self.ink = simdColor(from: ink)
        renderIfVisible()
    }

    func updatePlayback(visible: Bool, animated: Bool, interactive: Bool) {
        self.visible = visible
        self.animated = animated
        self.interactive = interactive
        if !visible { touching = false }
        applyPlayback()
    }

    private func renderIfVisible() {
        if visible, timer == nil {
            renderFrame()
        }
    }

    private func applyPlayback() {
        lastTickAt = CACurrentMediaTime()
        if visible, animated, !touching {
            resumeIdle()
        } else {
            freezeIdle()
        }
        if visible, (animated || interactive) {
            startAnimating()
        } else {
            stopAnimating()
            renderIfVisible()
        }
    }

    /// Contact is a grab: idle stops, and a stationary finger is just a pan of distance 0.
    func grab(at point: CGPoint, atTime: CFTimeInterval) {
        touching = true
        velocityX = 0
        velocityY = 0
        lastTouchPoint = point
        lastTouchAt = atTime
        freezeIdle()
        renderIfVisible()
    }

    func roll(to point: CGPoint, atTime now: CFTimeInterval) {
        let box = max(min(bounds.width, bounds.height), 1)
        let dx = Float((point.x - lastTouchPoint.x) / box)
        let dy = Float((point.y - lastTouchPoint.y) / box)
        let dt = Float(max(now - lastTouchAt, 1.0 / 240.0))
        velocityX = dx / dt
        velocityY = dy / dt
        rememberSpinDirection()
        lastTouchPoint = point
        lastTouchAt = now
        rollSurface(dx: dx, dy: dy)
        renderIfVisible()
    }

    func releaseGrab() {
        guard touching else { return }
        touching = false
        if animated {
            resumeIdle()
        }
        applyPlayback()
    }

    private func currentIdleSeconds() -> CFTimeInterval {
        if let since = idleRunningSince {
            return idleSeconds + (CACurrentMediaTime() - since)
        }
        return idleSeconds
    }

    private func freezeIdle() {
        idleSeconds = currentIdleSeconds()
        idleRunningSince = nil
    }

    private func resumeIdle() {
        guard animated, idleRunningSince == nil else { return }
        idleSeconds = currentIdleSeconds()
        idleRunningSince = CACurrentMediaTime()
    }

    /// Roll the visible front of the sphere so it follows the finger.
    /// Screen space is +X right, +Y down, +Z toward the camera.
    /// The rotation axis stays parallel to the phone face (`z = 0`).
    private func rollSurface(dx: Float, dy: Float) {
        let angle = hypot(dx, dy)
        guard angle > 1e-8 else { return }
        let axis = simd_normalize(SIMD3<Float>(-dy, dx, 0))
        userRotation = simd_normalize(simd_quatf(angle: angle, axis: axis) * userRotation)
    }

    private func rememberSpinDirection() {
        let speed = hypot(velocityX, velocityY)
        guard speed > 1e-6 else { return }
        idleDirX = velocityX / speed
        idleDirY = velocityY / speed
    }

    /// Keep spinning in view space around a stable axis parallel to the screen.
    /// Fast flicks decay toward idle speed without changing axis; then cruise.
    private func coastSpin(dt: Float) {
        if animated {
            rememberSpinDirection()
            let cruise = ThinkingOrbsSpin.idleSpeed
            let speed = hypot(velocityX, velocityY)
            let next = speed > cruise
                ? cruise + (speed - cruise) * exp(-3 * dt)
                : cruise
            velocityX = idleDirX * next
            velocityY = idleDirY * next
        } else {
            let speed = hypot(velocityX, velocityY)
            if speed < 0.02 {
                velocityX = 0
                velocityY = 0
            } else {
                let scale = exp(-3 * dt)
                velocityX *= scale
                velocityY *= scale
            }
        }
        rollSurface(dx: velocityX * dt, dy: velocityY * dt)
    }

    private func userRotationRows() -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        let matrix = simd_float3x3(userRotation)
        return (
            SIMD4(matrix.columns.0.x, matrix.columns.1.x, matrix.columns.2.x, 0),
            SIMD4(matrix.columns.0.y, matrix.columns.1.y, matrix.columns.2.y, 0),
            SIMD4(matrix.columns.0.z, matrix.columns.1.z, matrix.columns.2.z, 0)
        )
    }

    private func startAnimating() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: renderQueue)
        source.schedule(
            deadline: .now(),
            repeating: .nanoseconds(1_000_000_000 / framesPerSecond),
            leeway: .milliseconds(1)
        )
        source.setEventHandler { [weak self] in
            autoreleasepool { self?.tick() }
        }
        timer = source
        source.resume()
    }

    private func stopAnimating() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard visible else { return }
        let now = CACurrentMediaTime()
        let dt = Float(max(now - lastTickAt, 0))
        lastTickAt = now
        if !touching {
            coastSpin(dt: dt)
        }
        renderFrame()
    }

    private func refreshFitIfNeeded() {
        let box = Double(min(bounds.width, bounds.height))
        guard box > 0, abs(box - cachedFitSize) > 0.5 else { return }
        cachedFit = Float(thinkingOrbsFit(size: box))
        cachedFitSize = box
    }

    private func renderFrame() {
        guard visible, bounds.width > 0, bounds.height > 0 else { return }
        guard inFlightFrames.wait(timeout: .now()) == .success else { return }
        var submitted = false
        defer {
            if !submitted { inFlightFrames.signal() }
        }
        refreshFitIfNeeded()
        guard let drawable = metalLayer.nextDrawable() else { return }

        let box = Float(min(bounds.width, bounds.height))
        let seconds = currentIdleSeconds()
        let rows = userRotationRows()
        var uniforms = ThinkingOrbsGPUUniforms(
            phase: Float(thinkingOrbsPhase(period: Double(ThinkingOrbsSpin.idlePeriod), speed: 1, reverse: false, startAt: 0, seconds: seconds)),
            size: box,
            fit: cachedFit,
            dotScale: Float(thinkingOrbsDotScale(size: Double(box))),
            contentsScale: Float(contentsScale),
            pad0: 0,
            viewport: SIMD2(Float(drawable.texture.width), Float(drawable.texture.height)),
            origin: SIMD2((Float(bounds.width) - box) * 0.5, (Float(bounds.height) - box) * 0.5),
            pad1: SIMD2(0, 0),
            userR0: rows.0,
            userR1: rows.1,
            userR2: rows.2,
            accent: accent,
            ink: ink
        )

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
        let semaphore = inFlightFrames
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
        commandBuffer.present(drawable)
        submitted = true
        commandBuffer.commit()
        bufferIndex = (bufferIndex + 1) % ThinkingOrbsGPU.bufferCount
    }
}

private enum ThinkingOrbsGPU {
    static let dotCount = 160
    static let bufferCount = 3
}

private enum ThinkingOrbsSpin {
    static let idlePeriod: Float = 4.6
    static let idleSpeed: Float = (2 * Float.pi) / idlePeriod
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
    var userR0: SIMD4<Float>
    var userR1: SIMD4<Float>
    var userR2: SIMD4<Float>
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

/// Begins on finger down so a parent scroll/WebView/RN touch handler cannot steal the grab later.
private final class ThinkingOrbsGrabRecognizer: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1 else {
            state = .failed
            return
        }
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .began || state == .changed else { return }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .began || state == .changed else { return }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .began || state == .changed {
            state = .cancelled
        }
    }
}
