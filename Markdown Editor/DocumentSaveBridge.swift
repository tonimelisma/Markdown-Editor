//
//  DocumentSaveBridge.swift
//  Markdown Editor
//

import AppKit

// REQ-017/075: operation-scoped Save via owning NSDocument (no view-hierarchy discovery).

@MainActor
protocol DocumentSaving: AnyObject {
    func saveDocument() async -> DocumentSaveOutcome
}

/// REQ-017: an operation-scoped save distinguishes a completed write, user cancellation, and
/// an attempted save that failed. Callers that need to decide a later operation's outcome must
/// not collapse those cases into AppKit's completion Boolean.
nonisolated enum DocumentSaveOutcome: Sendable, Equatable {
    case succeeded
    case cancelled
    case failed
}

@MainActor
enum DocumentSaveBridge {
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
