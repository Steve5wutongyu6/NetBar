//
//  EngineBridge.swift
//  NetBar
//
//  Thin Swift wrapper over the Rust engine. The engine owns menu composition
//  (sections, ranking, folding); the app owns presentation.
//

import Foundation

enum EngineBridge {
    /// Builds the menu for a capture. Falls back to an empty menu if the engine
    /// returns a reply the app cannot decode.
    static func render(_ input: NBEngineInput) -> NBEngineOutput {
        guard let data = input.jsonData(),
              let request = String(data: data, encoding: .utf8) else {
            return emptyOutput()
        }
        // The engine reads a C string, so the request has to be NUL terminated:
        // `withCString` supplies the terminator, a bare `Data` does not.
        let output = request.withCString { pointer -> NBEngineOutput? in
            guard let reply = netbar_node_json(pointer) else { return nil }
            defer { netbar_string_free(UnsafeMutablePointer(mutating: reply)) }
            return NBEngineOutputFromJSONData(Data(bytes: reply, count: strlen(reply)))
        }
        return output ?? emptyOutput()
    }

    static var version: String {
        guard let pointer = netbar_engine_version() else { return "unknown" }
        return String(cString: pointer)
    }

    private static func emptyOutput() -> NBEngineOutput {
        let output = NBEngineOutput()
        output.items = []
        return output
    }
}
