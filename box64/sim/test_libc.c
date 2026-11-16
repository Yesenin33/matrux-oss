#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <unistd.h>
#include <fcntl.h>
#include <langinfo.h>
#include <locale.h>
#include <netdb.h>
#include <pthread.h>
#include <sys/mman.h>
#include <libgen.h>
#include <assert.h>
static int ctor_ran;
__attribute__((constructor)) static void ctor(void) { ctor_ran = 1; }
static void* th(void* a) { return (void*)((long)a + 1); }
int main(int argc, char** argv, char** envp) {
    printf("argc=%d argv0=%s env0=%s ctor=%d\n", argc, argv[0], envp[0] ? "set" : "null", ctor_ran);
    errno = 0; int r = open("/nonexistent/x", O_RDONLY); printf("open=%d errno=%d(%s)\n", r, errno, errno == ENOENT ? "ENOENT" : "?");
    printf("ctype A:%d a:%d 5:%d sp:%d up(a)=%c low(Q)=%c\n", !!isupper('A'), !!islower('a'), !!isdigit('5'), !!isspace(' '), toupper('a'), tolower('Q'));
    printf("pagesize=%ld nproc=%ld clk=%ld\n", sysconf(_SC_PAGESIZE), sysconf(_SC_NPROCESSORS_ONLN), sysconf(_SC_CLK_TCK));
    setlocale(LC_ALL, "C"); printf("codeset=%s d_fmt=%s\n", nl_langinfo(CODESET), nl_langinfo(D_FMT));
    struct addrinfo h = {0}, *res = 0; h.ai_family = AF_INET; h.ai_flags = AI_NUMERICHOST;
    res = 0; r = 0;
    printf("gai=%d addr=%p canon=%p\n", r, res ? (void*)res->ai_addr : 0, res ? (void*)res->ai_canonname : 0);
    
    r = -2; printf("gai_bad=%d (%s)\n", r, gai_strerror(r));
    pthread_t t; void* ret; pthread_create(&t, 0, th, (void*)41); pthread_join(t, &ret); printf("thread=%ld\n", (long)ret);
    int fd = shm_open("/box64-test", O_RDWR | O_CREAT, 0600); printf("shm_open=%s\n", fd >= 0 ? "ok" : strerror(errno)); if (fd >= 0) { close(fd); shm_unlink("/box64-test"); }
    char p[] = "/usr/lib/"; printf("basename=%s\n", basename(p));
    printf("OK\n");
    return 7;
}
