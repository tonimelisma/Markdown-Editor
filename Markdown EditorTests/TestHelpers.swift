//
//  TestHelpers.swift
//  Markdown EditorTests
//

import Foundation

extension Result {
    func get() -> Success? {
        if case .success(let value) = self { return value }
        return nil
    }
}
