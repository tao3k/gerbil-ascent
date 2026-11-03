/* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
 * SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later */
/* Independent consumer of the standard Gerbil build product; no SDK runtime. */
#include "ascent.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define REQUIRE(test) do { if (!(test)) { \
  fprintf(stderr, "ABI consumer failed at line %d: %s\n", __LINE__, #test); \
  return 1; } } while (0)

int main(int argc, char **argv) {
  REQUIRE(argc == 2);
  void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) { fprintf(stderr, "%s\n", dlerror()); return 1; }
  uint32_t (*version)(void) = (uint32_t (*)(void))dlsym(library, "ascent_abi_version");
  int32_t (*init)(void) = (int32_t (*)(void))dlsym(library, "ascent_runtime_init");
  int32_t (*shutdown)(void) = (int32_t (*)(void))dlsym(library, "ascent_runtime_shutdown");
  int32_t (*request)(const uint8_t *, size_t, ascent_result *) =
    (int32_t (*)(const uint8_t *, size_t, ascent_result *))dlsym(library, "ascent_request");
  void (*release)(ascent_result *) =
    (void (*)(ascent_result *))dlsym(library, "ascent_result_release");
  REQUIRE(version && init && shutdown && request && release);
  REQUIRE(version() == 1 && init() == 0);
  const uint8_t input[] = "{\"operation\":\"describe\"}";
  ascent_result result = {0};
  REQUIRE(request(input, sizeof(input) - 1, &result) == 0);
  REQUIRE(result.status == 0 && result.payload && result.length > 0);
  char *text = malloc(result.length + 1);
  REQUIRE(text);
  memcpy(text, result.payload, result.length);
  text[result.length] = '\0';
  REQUIRE(strstr(text, "\"abi\":1"));
  puts(text);
  free(text);
  release(&result);
  REQUIRE(result.payload == NULL && result.length == 0);
  REQUIRE(shutdown() == 0);
  REQUIRE(request(input, sizeof(input) - 1, &result) == -2);
  release(&result);
  REQUIRE(dlclose(library) == 0);
  puts("ABI-CONSUMER-OK");
  return 0;
}
