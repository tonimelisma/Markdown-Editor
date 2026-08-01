//
//  EncodedImageResourceTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

struct EncodedImageResourceTests {
    @Test func rejectsOversizedEncodedFileBeforeReadAndDecode() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("encoded-image-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("large.png")
        FileManager.default.createFile(atPath: imageURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: imageURL)
        try handle.truncate(atOffset: UInt64(LocalImageDecoder.maxEncodedFileBytes) + 1)
        try handle.close()

        let result = LocalImageDecoder.decode(
            destination: imageURL.lastPathComponent,
            documentURL: directory.appendingPathComponent("document.md")
        )
        #expect(result == .failure(.encodedFileTooLarge))
    }
}
