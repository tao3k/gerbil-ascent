;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/ffi (only-in "engine-api.ss" ascent-engine-dispatch)
        (only-in :std/encoding/json json->string))
(export ascent-engine-dispatch)
(C-ffi-macrology)
(C-declare #<<C
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
typedef struct { int32_t status; uint8_t *payload; size_t length; } ascent_result;
void ascent_result_release(ascent_result *r) {
  if (!r) return;
  free(r->payload); r->payload=NULL; r->length=0; r->status=0;
}
C
)
(def-C-type ascent_result "ascent_result")
(def-C-type ascent-result-pointer (pointer ascent_result (ascent-result-pointer)))
(def-C-lambda result-status (ascent-result-pointer) int32 "___return (___arg1->status);")
(def-C-lambda result-status-set! (ascent-result-pointer int32) void "___arg1->status=___arg2;")
(def-C-lambda result-copy! (ascent-result-pointer scheme-object) void #<<C
free(___arg1->payload); ___arg1->payload=NULL; ___arg1->length=U8_LEN(___arg2);
___arg1->payload=(uint8_t*)malloc(___arg1->length+1);
if (!___arg1->payload) { ___arg1->length=0; ___arg1->status=-5; ___return; }
memcpy(___arg1->payload,U8_DATA(___arg2),___arg1->length);
___arg1->payload[___arg1->length]=0;
C
)
(def (invoke input result)
   (with-catch
    (lambda (exception)
      (result-status-set! result -1)
      (result-copy! result
        (string->utf8 (json->string
          (hash ("error" "scheme request rejected")))))
      (result-status result))
    (lambda ()
      (result-status-set! result 0)
      (result-copy! result (string->utf8 (ascent-engine-dispatch input)))
      (result-status result))))
(begin-foreign
 (c-define (ascent-scheme-dispatch input result) (UTF-8-string ascent-result-pointer) int32
   "ascent_scheme_dispatch" "extern"
   (gerbil-ascent/interface/c-api#invoke input result)))
