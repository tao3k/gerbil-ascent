/* SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later */
/* Diagnostic only: private Darwin runtime images, owner-affine lifetime. */
#include <dlfcn.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

typedef struct { pthread_mutex_t mutex; pthread_cond_t cond; unsigned target, arrived, generation; } barrier;
static void wait_barrier(barrier *b) {
  pthread_mutex_lock(&b->mutex);
  unsigned generation = b->generation;
  if (++b->arrived == b->target) { b->arrived = 0; ++b->generation; pthread_cond_broadcast(&b->cond); }
  else { while (generation == b->generation) pthread_cond_wait(&b->cond, &b->mutex); }
  pthread_mutex_unlock(&b->mutex);
}
static void entered(void *data) { wait_barrier(data); }
static uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000000000 + t.tv_nsec; }
static void require(int condition, const char *message) {
  if (!condition) { fprintf(stderr, "VM-FAIL %s: %s\n", message, dlerror()); _Exit(2); }
}
static void *symbol(void *image, const char *name) { void *p = dlsym(image, name); require(p != NULL, name); return p; }
static pthread_mutex_t lifecycle = PTHREAD_MUTEX_INITIALIZER;
static barrier host, simultaneous;
static uint32_t components, groups, width, owners, samples;
typedef struct { unsigned id; const char *path; uintptr_t state; int64_t rows; int valid; } worker;
static void *run_worker(void *argument) {
  worker *w = argument;
  pthread_mutex_lock(&lifecycle);
  void *image = dlopen(w->path, RTLD_NOW | RTLD_LOCAL);
  require(image != NULL, "dlopen");
  int32_t (*init)(void) = symbol(image, "ascent_vm_init");
  int32_t (*cleanup)(void) = symbol(image, "ascent_vm_cleanup");
  uintptr_t (*state)(void) = symbol(image, "ascent_vm_state");
  uint32_t (*capabilities)(void) = symbol(image, "ascent_vm_capabilities");
  int32_t (*prepare)(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t) = symbol(image, "ascent_vm_prepare");
  int64_t (*solve)(void *) = symbol(image, "ascent_vm_run");
  int32_t (*validate)(void) = symbol(image, "ascent_vm_validate");
  require(capabilities() == 3, "require multiple VMs and single-threaded VM ABI");
  require(init() == 0, "official setup");
  w->state = state();
  require(prepare(components,groups,width,w->id,owners) == (int32_t)w->id+1, "prepare, GC, single processor");
  pthread_mutex_unlock(&lifecycle);
  wait_barrier(&host);
  struct { void (*entered)(void *); void *data; } context = { entered, &simultaneous };
  for (unsigned s=0; s<=samples; ++s) {
    wait_barrier(&host);
    w->rows = solve(&context);
    require(w->rows >= 0, "Scheme solve");
    wait_barrier(&host);
    w->valid = validate();
    wait_barrier(&host);
  }
  pthread_mutex_lock(&lifecycle);
  require(cleanup() == 0, "owner-affine cleanup");
  pthread_mutex_unlock(&lifecycle);
  /* Do not dlclose: process-wide signal/timer hook ownership is unqualified. */
  return NULL;
}
int main(int argc, char **argv) {
  require(argc >= 7, "usage: runner components groups width owners samples image...");
  components = (uint32_t)strtoul(argv[1],NULL,10); groups = (uint32_t)strtoul(argv[2],NULL,10);
  width = (uint32_t)strtoul(argv[3],NULL,10); owners = (uint32_t)strtoul(argv[4],NULL,10);
  samples = (uint32_t)strtoul(argv[5],NULL,10);
  require(owners > 0 && argc == (int)owners+6, "image per owner");
  host = (barrier){ PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER, owners+1, 0, 0 };
  simultaneous = (barrier){ PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER, owners, 0, 0 };
  worker *workers = calloc(owners,sizeof(*workers)); pthread_t *threads = calloc(owners,sizeof(*threads));
  require(workers && threads, "host allocation");
  uint64_t startup = now_ns();
  for (unsigned i=0;i<owners;++i) { workers[i]=(worker){ .id=i, .path=argv[6+i] }; require(pthread_create(&threads[i],NULL,run_worker,&workers[i])==0,"pthread_create"); }
  wait_barrier(&host);
  for (unsigned i=0;i<owners;++i) {
    require(workers[i].state != 0,"non-null global state");
    for (unsigned j=0;j<i;++j) require(workers[i].state != workers[j].state,"distinct VM global states");
    fprintf(stderr,"VM-OWNER id=%u global-state=%" PRIxPTR " processors=1\n",i,workers[i].state);
  }
  fprintf(stderr,"VM-STARTUP ns=%" PRIu64 " owners=%u\n",now_ns()-startup,owners);
  uint64_t expected = (uint64_t)components*groups*width*(width-1)/2;
  for (unsigned s=0;s<=samples;++s) {
    uint64_t begin = now_ns(); wait_barrier(&host); wait_barrier(&host); uint64_t duration=now_ns()-begin;
    wait_barrier(&host); uint64_t total=0;
    for (unsigned i=0;i<owners;++i) { require(workers[i].valid==(int)i+1,"exact tuples and independent Scheme marker"); total+=(uint64_t)workers[i].rows; }
    require(total==expected,"complete partition union");
    if(s>0) { printf("%u\t%u\t%u\tscheme-multivm-image\t%u\t%u\t%" PRIu64 "\t%" PRIu64 "\n",components,groups,width,owners,s-1,duration,total); fflush(stdout); }
  }
  uint64_t teardown=now_ns();
  for (unsigned i=0;i<owners;++i) require(pthread_join(threads[i],NULL)==0,"owner join");
  fprintf(stderr,"VM-TEARDOWN ns=%" PRIu64 " joined=%u\n",now_ns()-teardown,owners);
  free(threads);free(workers);return 0;
}
