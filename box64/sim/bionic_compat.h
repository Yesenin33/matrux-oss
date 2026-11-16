/* Android-sim: bionic-only API on glibc host (test harness only) */
#pragma once
#ifndef __ASSEMBLER__
#include <errno.h>
#include <netdb.h>
int* __errno(void);
int* __get_h_errno(void);
void __assert2(const char*, int, const char*, const char*);
#endif
#ifndef __ASSEMBLER__
#include <signal.h>
typedef sigset_t sigset64_t;
#endif
/* bionic/uapi aarch64: _NSIG=64, one 64-bit word */
#define _NSIG_WORDS 1
/* env.c defines its own static shm_open under ANDROID (bionic has none) */
#define shm_open box64sim_shm_open
#define shm_unlink box64sim_shm_unlink
