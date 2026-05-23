import SwiftUI
import AppKit
import QuartzCore
import BunnyshellCore

class TerminalNSView: NSView {
    var onInput: ((String) -> Void)? = nil
    var onInitRenderer: (() -> Void)? = nil
    
    override var acceptsFirstResponder: Bool { true }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
    }
    
    override func makeBackingLayer() -> CALayer {
        return CAMetalLayer()
    }
    
    override func keyDown(with event: NSEvent) {
        if let chars = event.characters {
            onInput?(chars)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window != nil {
            self.wantsLayer = true
            onInitRenderer?()
        }
    }
}

struct TerminalView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    let ptyManager: PtyManager
    
    func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView()
        view.wantsLayer = true
        
        let ptr = UInt64(UInt(bitPattern: UnsafeRawPointer(Unmanaged.passUnretained(view).toOpaque())))
        
        view.onInput = { input in
            if let data = input.data(using: .utf8) {
                try? ptyManager.write(id: session.id, data: data)
            }
        }
        
        view.onInitRenderer = {
            let width = max(100, UInt32(view.bounds.width))
            let height = max(100, UInt32(view.bounds.height))
            if let renderer = try? TerminalRenderer(nsviewPtr: ptr, width: width, height: height) {
                session.renderer = renderer
                // Register renderer in core registry and obtain a handle usable
                // by the Tauri/native-surface bridge. This allows the webview's
                // rendererPool to call into ns_render_lines using the same
                // renderer instance.
                if let handle = try? BunnyshellCore.register_renderer(renderer) {
                    session.rendererHandle = handle
                }
                session.triggerRender()
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: TerminalNSView, context: Context) {
        let width = UInt32(nsView.bounds.width)
        let height = UInt32(nsView.bounds.height)
        if width > 0 && height > 0 {
            nsView.sessionRendererResize(session: session, width: width, height: height)
        }
    }
}

extension TerminalNSView {
    func sessionRendererResize(session: TerminalSession, width: UInt32, height: UInt32) {
        guard self.window != nil else { return }
        session.renderer?.resize(width: width, height: height)
        session.triggerRender()
    }
}
