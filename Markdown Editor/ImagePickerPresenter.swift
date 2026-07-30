import AppKit
import UniformTypeIdentifiers

@MainActor
protocol ImagePicking: AnyObject { func pickImages() async -> [URL] }

@MainActor
final class OpenPanelImagePicker: ImagePicking {
    func pickImages() async -> [URL] {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .heif]
            panel.begin { continuation.resume(returning: $0 == .OK ? panel.urls : []) }
        }
    }
}
