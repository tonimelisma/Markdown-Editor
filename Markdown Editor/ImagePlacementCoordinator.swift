//
//  ImagePlacementCoordinator.swift
//  Markdown Editor
//

import AppKit
import SwiftUI
import Combine

// REQ-060/069–076: main-actor owner of one paste/drop placement transaction.

@MainActor
final class ImagePlacementCoordinator: ObservableObject {
    enum AlertKind: Equatable {
        case error(String)
        case warning(String)
        case info(String)
    }

    @Published var alert: AlertKind?

    private let service = ImagePlacementService()
    private var busy = false
    private var pendingItems: [ImagePlacementItem]?
    private var awaitingSave = false
    private weak var textView: MarkdownSourceTextView?
    private var lastDocumentParent: URL?
    private var knownGeneratedFilenames: Set<String> = []
    private static let generatedAssetPattern = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(assets/([^)\s]+)\)"#
    )

    private var saveSheetObserver: NSObjectProtocol?

    func attach(textView: MarkdownSourceTextView) {
        self.textView = textView
    }

    func updateDocumentURL(_ url: URL?) {
        let newParent = url?.deletingLastPathComponent()
        if let old = lastDocumentParent, let newParent, old != newParent {
            checkBrokenAssetReferences(documentURL: url)
        }
        lastDocumentParent = newParent

        if awaitingSave, let url {
            awaitingSave = false
            clearSaveSheetObserver()
            if let items = pendingItems {
                pendingItems = nil
                Task { await runPlacement(items: items, documentURL: url) }
            }
        }
    }

    // REQ-060/064: begin placement from already-classified immutable items.
    func handleImageAction(items: [ImagePlacementItem], documentURL: URL?) {
        guard !items.isEmpty else { return }
        if busy {
            alert = .error("Wait for the current image action to finish.")
            return
        }
        if let documentURL {
            Task { await runPlacement(items: items, documentURL: documentURL) }
            return
        }
        // REQ-075: untitled → Save first; cancel Save cancels placement.
        pendingItems = items
        awaitingSave = true
        watchForSavePanelDismissal()
        let saved = NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
        if !saved {
            clearSaveSheetObserver()
            awaitingSave = false
            pendingItems = nil
            alert = .error("Save the document before adding images.")
        }
    }

    /// REQ-060: receive file promises into staging, then place as ordinary file bytes.
    func handleFilePromises(_ receivers: [NSFilePromiseReceiver], documentURL: URL?) {
        guard !receivers.isEmpty else { return }
        if busy {
            alert = .error("Wait for the current image action to finish.")
            return
        }
        Task { @MainActor in
            do {
                let items = try await Self.receivePromiseItems(receivers)
                self.handleImageAction(items: items, documentURL: documentURL)
            } catch {
                self.alert = .error("Could not receive promised image files.")
            }
        }
    }

    private static func receivePromiseItems(_ receivers: [NSFilePromiseReceiver]) async throws -> [ImagePlacementItem] {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-editor-promise-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        var items: [ImagePlacementItem] = []
        for receiver in receivers {
            let urls: [URL] = try await withCheckedThrowingContinuation { cont in
                receiver.receivePromisedFiles(
                    atDestination: staging,
                    options: [:],
                    operationQueue: OperationQueue()
                ) { url, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: [url])
                    }
                }
            }
            for url in urls {
                guard let item = ImagePasteboardClassifier.itemFromFileURL(url) else {
                    throw ImagePlacementError.unsupportedOrCorrupt
                }
                items.append(item)
            }
        }
        guard !items.isEmpty else { throw ImagePlacementError.unsupportedOrCorrupt }
        return items
    }

    private func watchForSavePanelDismissal() {
        clearSaveSheetObserver()
        saveSheetObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndSheetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.finishAwaitingSaveIfStillUntitled()
            }
        }
    }

    private func finishAwaitingSaveIfStillUntitled() {
        guard awaitingSave else { return }
        if textView?.documentURL == nil {
            noteSaveCancelled()
        }
    }

    private func clearSaveSheetObserver() {
        if let saveSheetObserver {
            NotificationCenter.default.removeObserver(saveSheetObserver)
            self.saveSheetObserver = nil
        }
    }

    func noteSaveCancelled() {
        guard awaitingSave else { return }
        awaitingSave = false
        pendingItems = nil
        clearSaveSheetObserver()
        alert = .info("Image action cancelled — document was not saved.")
    }

    /// Test seam: simulate untitled placement waiting for Save (REQ-075).
    func prepareUntitledPlacementForTesting(_ items: [ImagePlacementItem]) {
        pendingItems = items
        awaitingSave = true
    }

    private func runPlacement(items: [ImagePlacementItem], documentURL: URL) async {
        guard let textView else { return }
        busy = true
        defer { busy = false }

        let selected = textView.selectedRange()
        let generation = textView.beginTrackingPlacement(range: selected)

        do {
            let placed = try await service.place(items: items, documentURL: documentURL)
            guard let tracker = textView.trackedPlacement(for: generation), !tracker.isCancelled else {
                // REQ-072: files may exist but do not insert source.
                for p in placed where p.wasCreatedByThisTransaction {
                    knownGeneratedFilenames.insert(p.filename)
                }
                alert = .warning("Images were saved to assets/, but the insertion point changed — references were not inserted.")
                textView.endTrackingPlacement(generation)
                return
            }

            let markdown = placed.map(\.markdown).joined(separator: "\n")
            // REQ-069/070/073/074: one undoable replacement; never delete assets on undo.
            textView.insertImageMarkdown(markdown, at: tracker.range, selectEmptyDescription: placed.count == 1)
            for p in placed {
                knownGeneratedFilenames.insert(p.filename)
            }
            textView.endTrackingPlacement(generation)
        } catch let error as ImagePlacementError {
            textView.endTrackingPlacement(generation)
            alert = .error(message(for: error))
        } catch is CancellationError {
            textView.endTrackingPlacement(generation)
        } catch {
            textView.endTrackingPlacement(generation)
            alert = .error(error.localizedDescription)
        }
    }

    // REQ-076: warn when parent change breaks generated assets/… references.
    private func checkBrokenAssetReferences(documentURL: URL?) {
        guard let textView, let documentURL else { return }
        let text = textView.string as NSString
        let full = NSRange(location: 0, length: text.length)
        var broken = false
        Self.generatedAssetPattern.enumerateMatches(in: text as String, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let filename = text.substring(with: match.range(at: 2))
            guard knownGeneratedFilenames.contains(filename) else { return }
            let assets = documentURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
            let file = assets.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: file.path) {
                broken = true
            }
        }
        if broken {
            alert = .warning("This document’s assets/ references no longer resolve after the file was moved. Companion files were not moved automatically.")
        }
    }

    private func message(for error: ImagePlacementError) -> String {
        switch error {
        case .noDocumentURL:
            return "Save the document before adding images."
        case .unsafeDestination:
            return "Cannot use the assets/ folder (symlink, alias, or unsafe path)."
        case .unsupportedOrCorrupt:
            return "Unsupported or corrupt image."
        case .typeMismatch:
            return "Image type does not match a supported format."
        case .writeFailed, .partialFailure:
            return "Could not write image files. Nothing was inserted."
        }
    }
}
