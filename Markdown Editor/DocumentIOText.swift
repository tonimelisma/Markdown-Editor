//
//  DocumentIOText.swift
//  Markdown Editor
//

import Foundation
import Synchronization

/// Thread-safe, Sendable byte-faithful text snapshot for NSDocument I/O.
///
/// // REQ-018/088: Synchronization.Mutex — no `nonisolated(unsafe)`.
final class DocumentIOText: Sendable {
    private let lock = Mutex<String>("")

    nonisolated func store(_ value: String) {
        lock.withLock { $0 = value }
    }

    nonisolated func load() -> String {
        lock.withLock { $0 }
    }

    nonisolated func data() -> Data {
        MarkdownDocumentData(text: load()).data()
    }
}
