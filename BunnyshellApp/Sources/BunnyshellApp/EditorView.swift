import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    let path: String
    @Binding var text: String
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor(hex: "0B0E14") ?? .black
        textView.textColor = NSColor(hex: "E6EDF3") ?? .white
        textView.insertionPointColor = NSColor(hex: "387CFF") ?? .blue
        
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width, .height]
        
        textView.string = text
        textView.delegate = context.coordinator
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.setSelectedRanges(selectedRanges, affinity: .upstream, stillSelecting: false)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        
        init(_ parent: EditorView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}


