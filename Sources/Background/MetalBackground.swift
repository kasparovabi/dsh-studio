import MetalKit
import SwiftUI

struct BgUniforms {
    var time: Float
    var activity: Float
    var dark: Float
    var resolution: SIMD2<Float>
    var mouse: SIMD2<Float>
}

final class BackgroundRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let lightPoints: MTLRenderPipelineState
    private let lightTraces: MTLRenderPipelineState
    private let darkPoints: MTLRenderPipelineState
    private let darkTraces: MTLRenderPipelineState
    private let start = CACurrentMediaTime()
    private let pointCount = 900 + 60_000
    private let traceCount = 11 * 53 * 2
    var mouseTarget = SIMD2<Float>(0.5, 0.5)
    var activity: Float = 0.15
    var dark = false
    private var mouse = SIMD2<Float>(0.5, 0.5)
    private var smoothedActivity: Float = 0.15

    init?(device: MTLDevice) {
        guard let q = device.makeCommandQueue(),
              let lib = device.makeDefaultLibrary() else { return nil }

        // On paper the particles are pigment, so they blend over the ground the
        // ordinary way. On a dark ground they are light, and only an additive
        // pass makes overlapping ones glow instead of flattening each other.
        func pipeline(_ vertexName: String, _ fragmentName: String, additive: Bool) -> MTLRenderPipelineState? {
            guard let v = lib.makeFunction(name: vertexName),
                  let f = lib.makeFunction(name: fragmentName) else { return nil }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = v
            desc.fragmentFunction = f
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].rgbBlendOperation = .add
            desc.colorAttachments[0].sourceRGBBlendFactor = additive ? .one : .sourceAlpha
            desc.colorAttachments[0].destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        guard let lp = pipeline("bg_vertex", "bg_fragment", additive: false),
              let lt = pipeline("bg_trace_vertex", "bg_trace_fragment", additive: false),
              let dp = pipeline("bg_vertex", "bg_fragment", additive: true),
              let dt = pipeline("bg_trace_vertex", "bg_trace_fragment", additive: true) else { return nil }
        queue = q
        lightPoints = lp
        lightTraces = lt
        darkPoints = dp
        darkTraces = dt
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: rpd) else { return }
        smoothedActivity += (activity - smoothedActivity) * 0.012
        mouse += (mouseTarget - mouse) * 0.05
        var uniforms = BgUniforms(
            time: Float(CACurrentMediaTime() - start),
            activity: smoothedActivity,
            dark: dark ? 1 : 0,
            resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            mouse: mouse
        )
        enc.setVertexBytes(&uniforms, length: MemoryLayout<BgUniforms>.stride, index: 0)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<BgUniforms>.stride, index: 0)
        enc.setRenderPipelineState(dark ? darkPoints : lightPoints)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointCount)
        enc.setRenderPipelineState(dark ? darkTraces : lightTraces)
        enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: traceCount)
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

struct MetalBackground: NSViewRepresentable {
    var activity: Float
    var dark: Bool

    static func ground(dark: Bool) -> MTLClearColor {
        dark
            ? MTLClearColor(red: 0.055, green: 0.047, blue: 0.035, alpha: 1)
            : MTLClearColor(red: 0.958, green: 0.961, blue: 0.968, alpha: 1)
    }

    final class Coordinator {
        var renderer: BackgroundRenderer?
        var monitor: Any?
        var occlusionToken: NSObjectProtocol?

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let occlusionToken { NotificationCenter.default.removeObserver(occlusionToken) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = BackgroundRenderer(device: device) else { return view }
        view.device = device
        // The field drifts slowly, so half the frames carry all of the motion
        // anyone can see and the fill cost halves with them.
        view.preferredFramesPerSecond = 30
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MetalBackground.ground(dark: dark)
        view.delegate = renderer
        renderer.dark = dark
        context.coordinator.renderer = renderer
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak view] ev in
            if let view {
                let p = view.convert(ev.locationInWindow, from: nil)
                let size = view.bounds.size
                if size.width > 1, size.height > 1 {
                    renderer.mouseTarget = SIMD2<Float>(
                        Float(min(max(p.x / size.width, 0), 1)),
                        Float(min(max(1 - p.y / size.height, 0), 1))
                    )
                }
            }
            return ev
        }
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.activity = activity
        context.coordinator.renderer?.dark = dark
        view.clearColor = MetalBackground.ground(dark: dark)
        guard let window = view.window else { return }
        window.acceptsMouseMovedEvents = true
        if context.coordinator.occlusionToken == nil {
            context.coordinator.occlusionToken = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak view, weak window] _ in
                guard let view, let window else { return }
                view.isPaused = !window.occlusionState.contains(.visible)
            }
        }
    }
}
