import SwiftUI
import GhosttyKit

struct TerminalView: View {
    @ObservedObject var session: Ghostty.SurfaceView

    var body: some View {
        Ghostty.SurfaceWrapper(surfaceView: session)
    }
}
