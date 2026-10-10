/* SPDX-FileCopyrightText: 2026 tao3k team and Contributors
 * SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later */
#include "gambit.h"
#include "ascent.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#ifndef ASCENT_LINKER
#error "ASCENT_LINKER must name the compiler generated link unit"
#endif
___BEGIN_NEW_LNK
___DEF_NEW_LNK(ASCENT_LINKER)
___END_NEW_LNK
extern int32_t ascent_scheme_dispatch(char *, ascent_result *);
static pthread_mutex_t gate=PTHREAD_MUTEX_INITIALIZER;
static pthread_t owner;
static int state=0;
static int valid_utf8(const uint8_t *s, size_t n) {
  size_t i=0;
  while (i<n) {
    uint32_t cp; unsigned more; uint8_t b=s[i++];
    if (b<0x80) continue;
    if (b>=0xC2 && b<=0xDF) { cp=b&31; more=1; }
    else if (b>=0xE0 && b<=0xEF) { cp=b&15; more=2; }
    else if (b>=0xF0 && b<=0xF4) { cp=b&7; more=3; }
    else return 0;
    if (n-i<more) return 0;
    for (unsigned k=0;k<more;k++) {
      b=s[i++]; if ((b&0xC0)!=0x80) return 0; cp=(cp<<6)|(b&63);
    }
    if ((more==1 && cp<0x80) || (more==2 && cp<0x800) ||
        (more==3 && cp<0x10000) || (cp>=0xD800 && cp<=0xDFFF) || cp>0x10FFFF) return 0;
  }
  return 1;
}
uint32_t ascent_abi_version(void) { return 1; }
int32_t ascent_runtime_init(void) {
  int32_t rc=0;
  pthread_mutex_lock(&gate);
  if (state==2) rc=-2;
  else if (state==1) rc=pthread_equal(owner,pthread_self()) ? 0 : -3;
  else {
    ___setup_params_struct p; ___setup_params_reset(&p);
    p.version=___VERSION; p.linker=ASCENT_LINKER;
    p.debug_settings=___DEBUG_SETTINGS_INITIAL;
    if (___setup(&p)!=___FIX(___NO_ERR)) { state=2; rc=-2; }
    else { owner=pthread_self(); state=1; }
  }
  pthread_mutex_unlock(&gate); return rc;
}
int32_t ascent_request(const uint8_t *input, size_t length, ascent_result *r) {
  int32_t rc; char *copy;
  if (!r) return -4;
  ascent_result_release(r);
  if (!input || !length || length>1048576 || memchr(input,0,length) || !valid_utf8(input,length)) return r->status=-4;
  pthread_mutex_lock(&gate);
  if (state!=1) rc=-2;
  else if (!pthread_equal(owner,pthread_self())) rc=-3;
  else if (!(copy=malloc(length+1))) rc=-5;
  else { memcpy(copy,input,length); copy[length]=0;
    rc=ascent_scheme_dispatch(copy,r); free(copy); }
  r->status=rc; pthread_mutex_unlock(&gate); return rc;
}
int32_t ascent_runtime_shutdown(void) {
  int32_t rc=0; pthread_mutex_lock(&gate);
  if (state==1 && !pthread_equal(owner,pthread_self())) rc=-3;
  else if (state==1) { ___cleanup(); state=2; }
  else if (state==0) state=2;
  pthread_mutex_unlock(&gate); return rc;
}
