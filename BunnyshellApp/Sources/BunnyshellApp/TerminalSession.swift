import Foundation
import BunnyshellCore

class TerminalSession: ObservableObject, PtyCallback {
    let id: UInt32
    var lines: [String] = [""]
    var cols: UInt16 = 120
    var rows: UInt16 = 40
    var renderer: TerminalRenderer? = nil
    var rendererHandle: UInt64? = nil
    
    init(id: UInt32) {
        self.id = id
    }
    
    func onData(id: UInt32, data: Data) {
        if let rawText = String(data: data, encoding: .utf8) {
            let text = stripAnsi(rawText)
            DispatchQueue.main.async {
                self.append(text)
                self.triggerRender()
            }
        }
    }
    
    func onExit(id: UInt32, exitCode: Int32) {
        DispatchQueue.main.async {
            self.append("\r\n[Process completed with exit code \(exitCode)]\r\n")
            self.triggerRender()
        }
    }
    
    private func append(_ text: String) {
        for char in text {
            if char == "\n" {
                lines.append("")
                if lines.count > 1000 {
                    lines.removeFirst()
                }
            } else if char == "\r" {
                if let lastIdx = lines.indices.last {
                    lines[lastIdx] = ""
                }
            } else {
                if let lastIdx = lines.indices.last {
                    lines[lastIdx].append(char)
                }
            }
        }
    }
    
    func triggerRender() {
        guard let renderer = renderer else { return }
        let visibleLines = Array(lines.suffix(Int(rows)))
        try? renderer.render(lines: visibleLines)
    }
}

private let ansiRegex = try? NSRegularExpression(pattern: "\\\u{001B}\\[[0-9;]*[a-zA-Z]", options: [])

func stripAnsi(_ text: String) -> String {
    guard let regex = ansiRegex else {
        return text
    }
    let range = NSRange(text.startIndex..., in: text)
    return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
}
