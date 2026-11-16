#include <errno.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
int* __errno(void) { return &errno; }
int* __get_h_errno(void) { return &h_errno; }
void __assert2(const char* f, int l, const char* fn, const char* a) { fprintf(stderr, "assert %s:%d %s: %s\n", f, l, fn, a); abort(); }
void android_set_abort_message(const char* m) { (void)m; }
