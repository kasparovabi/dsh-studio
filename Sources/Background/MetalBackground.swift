import MetalKit
import SwiftUI

struct BgUniforms {
    var time: Float
    var activity: Float
    var resolution: SIMD2<Float>
    var mouse: SIMD2<Float>
}

final class BackgroundRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let start = CACurrentMediaTime()
    var mouseTarget = SIMD2<Float>(0.5, 0.5)
    var activity: Float = 0.15
    private var mouse = SIMD2<Float>(0.5, 0.5)
    private var smoothedActivity: Float = 0.15

    init?(device: MTLDevice) {
        guard let q = device.makeCommandQueue(),
              let lib = device.makeDefaultLibrary(),
              let v = lib.makeFunction(name: "bg_vertex"),
              let f = lib.makeFunction(name: "bg_fragment") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = v
        desc.fragmentFunction = f
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let p = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        queue = q
        pipeline = p
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
            resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            mouse: mouse
        )
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<BgUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

struct MetalBackground: NSViewRepresentable {
    var activity: Float

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
        view.preferredFramesPerSecond = 30
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = renderer
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
