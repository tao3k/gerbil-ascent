/* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later */
#define ___VERSION 409008
#include "gambit.h"
#include <stdint.h>
extern ___mod_or_lnk ___LNK_ascent__vm__diagnostic(___global_state_struct *);
extern int32_t ascent_vm_prepare(uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);
extern int64_t ascent_vm_run(void *);
extern int32_t ascent_vm_validate(void);
static int initialized;
int32_t ascent_vm_init(void) {
  ___setup_params_struct params;
  if (initialized) return -1;
  initialized = -1;
  ___setup_params_reset(&params);
  params.version = ___VERSION;
  params.linker = ___LNK_ascent__vm__diagnostic;
  if (___setup(&params) != ___FIX(___NO_ERR)) return -2;
  initialized = 1;
  return 0;
}
int32_t ascent_vm_cleanup(void) { if (initialized != 1) return -1; ___cleanup(); initialized = -1; return 0; }
uintptr_t ascent_vm_state(void) { return (uintptr_t)___GSTATE; }
uint32_t ascent_vm_capabilities(void) {
  uint32_t result = 0;
#ifndef ___SINGLE_VM
  result |= 1;
#endif
#ifdef ___SINGLE_THREADED_VMS
  result |= 2;
#endif
  return result;
}
