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
    ///
    /// JSON encode, engine call and JSON decode all run off the main thread: the
    /// reply for a full scan is a few kilobytes and the radio refresh happens on
    /// every event, so this must not compete with drawing the menu.
    static func render(_ input: NBEngineInput) async -> NBEngineOutput {
        await Task.detached(priority: .userInitiated) { renderSynchronously(input) }.value
    }

    /// The blocking form, for callers that already run off the main thread.
    static func renderSynchronously(_ input: NBEngineInput) -> NBEngineOutput {
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

    /// The engine's version string.
    ///
    /// `netbar_engine_version` returns a pointer to a static string owned by the
    /// engine, not a heap buffer, so there is nothing to free here — freeing it
    /// would corrupt the engine. The value is copied into a Swift string.
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
