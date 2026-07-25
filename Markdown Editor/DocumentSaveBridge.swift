//
//  DocumentSaveBridge.swift
//  Markdown Editor
//

import AppKit

// REQ-075: operation-scoped Save via owning NSDocument (RESEARCH-0006).

@MainActor
protocol DocumentSaving: AnyObject {
    func saveDocument() async -> Bool
}

@MainActor
enum DocumentSaveBridge {
    static func document(for view: NSView) -> NSDocument? {
        guard let window = view.window else { return nil }
        if let doc = NSDocumentController.shared.document(for: window) {
            return doc
        }
        return window.windowController?.document as? NSDocument
    }

    static func save(_ document: NSDocument) async -> Bool {
        await withCheckedContinuation { cont in
            let box = SaveResumeBox(cont)
            document.save(
                withDelegate: box,
                didSave: #selector(SaveResumeBox.didSave(_:didSaveSuccessfully:contextInfo:)),
                contextInfo: nil
            )
        }
    }
}

@MainActor
final class NSDocumentSavingAdapter: DocumentSaving {
    private let document: NSDocument
    init(document: NSDocument) { self.document = document }
    func saveDocument() async -> Bool {
        await DocumentSaveBridge.save(document)
    }
}

private final class SaveResumeBox: NSObject, @unchecked Sendable {
    private var cont: CheckedContinuation<Bool, Never>?
    private let lock = NSLock()

    init(_ cont: CheckedContinuation<Bool, Never>) {
        self.cont = cont
    }

    @objc func didSave(_ doc: NSDocument, didSaveSuccessfully flag: Bool, contextInfo: UnsafeMutableRawPointer?) {
        lock.lock()
        let c = cont
        cont = nil
        lock.unlock()
        c?.resume(returning: flag)
    }
}
