/* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
 * SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later */
#ifndef ASCENT_ENGINE_H
#define ASCENT_ENGINE_H
#include <stdint.h>
#include <stddef.h>
typedef struct { int32_t status; uint8_t *payload; size_t length; } ascent_result;
/* Same OS thread owns init, requests and shutdown. Shutdown is terminal.
 * Caller zero-initializes each result and releases its buffer after every call.
 * 0=success, -1=engine/parse error, -2=runtime state, -3=thread,
 * -4=invalid C arguments, -5=allocation failure. */
uint32_t ascent_abi_version(void);
int32_t ascent_runtime_init(void);
int32_t ascent_runtime_shutdown(void);
int32_t ascent_request(const uint8_t *input, size_t length, ascent_result *result);
void ascent_result_release(ascent_result *result);
#endif
