import AppKit

/// Notices a new screenshot, whether it was saved as a file or copied to the clipboard,
/// and can take a region capture itself when the user clicks "Capture and ask".
final class ScreenshotWatcher: NSObject {
    var onShot: ((String) -> Void)?
    var isEnabled: () -> Bool = { true }

    private let query = NSMetadataQuery()
    private var seen = Set<String>()
    private var clipboardTimer: Timer?
    private var clipboardCount = NSPasteboard.general.changeCount
    private var capturing = false

    func start() {
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture = 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(self, selector: #selector(queryUpdated(_:)),
                                               name: .NSMetadataQueryDidUpdate, object: query)
        query.start()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.pollClipboard()
        }
    }

    private func newCapturePath() -> String {
        Paths.ensure()
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return Paths.captures.appendingPathComponent("capture-\(stamp).png").path
    }

    @objc private func queryUpdated(_ note: Notification) {
        guard let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] else { return }
        for item in added {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !path.hasPrefix(Paths.captures.path), !seen.contains(path) else { continue }
            seen.insert(path)
            let created = (item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date) ?? .distantPast
            guard Date().timeIntervalSince(created) < 20, isEnabled() else { continue }
            // Keep our own copy, so the question still works if the user deletes the screenshot.
            let copy = newCapturePath()
            do {
                try FileManager.default.copyItem(atPath: path, toPath: copy)
                onShot?(copy)
            } catch {
                dlog("screenshot could not be read (folder permission?)")
            }
        }
    }

    private func pollClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != clipboardCount else { return }
        clipboardCount = pasteboard.changeCount
        guard isEnabled(), !capturing, Date() > ClipboardGuard.ignoreUntil else { return }
        let types = pasteboard.types ?? []
        // A screenshot copied with ⌃⇧⌘4 is image data only: no text, no file.
        guard types.contains(.png) || types.contains(.tiff),
              !types.contains(.string), !types.contains(.fileURL) else { return }
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: data),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let path = newCapturePath()
        guard (try? png.write(to: URL(fileURLWithPath: path))) != nil else { return }
        onShot?(path)
    }

    /// The system's own crosshair. Esc cancels and the completion gets nil.
    func captureRegion(completion: @escaping (String?) -> Void) {
        guard !capturing else { return }
        capturing = true
        let path = newCapturePath()
        seen.insert(path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", path]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.capturing = false
                completion(FileManager.default.fileExists(atPath: path) ? path : nil)
            }
        }
        do {
            try process.run()
        } catch {
            capturing = false
            completion(nil)
        }
    }

    /// Captures older than a week are removed.
    func cleanOldCaptures() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: Paths.captures, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for url in items {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            if Date().timeIntervalSince(created) > 7 * 24 * 3600 { try? fm.removeItem(at: url) }
        }
    }
}
