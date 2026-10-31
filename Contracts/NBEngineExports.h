//
//  NBEngineExports.h
//  NetBar
//
//  The only symbol the Rust staticlib exports. Strings are UTF-8; the caller
//  owns the returned buffer and frees it with `netbar_string_free`.
//

#ifndef NB_ENGINE_EXPORTS_H
#define NB_ENGINE_EXPORTS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Converts a UTF-8 JSON `NBEngineInput` into a UTF-8 JSON `NBEngineOutput`.
/// Returns a heap buffer with a NUL terminator; never NULL on valid input.
const char *netbar_node_json(const char *input_json);

/// Human readable version of the engine, for diagnostics.
///
/// The pointer refers to a string constant inside the engine: it stays valid for
/// the life of the process and must NOT be passed to `netbar_string_free`.
const char *netbar_engine_version(void);

/// Releases a buffer returned by the engine.
void netbar_string_free(char *buffer);

#ifdef __cplusplus
}
#endif

#endif
