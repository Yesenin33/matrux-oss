#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <setjmp.h>
#include <ucontext.h>
static volatile int got_usr1, got_segv;
static sigjmp_buf jb;
static void on_usr1(int sig, siginfo_t* si, void* uc) { (void)si; (void)uc; got_usr1 = sig; }
static void on_segv(int sig, siginfo_t* si, void* p) {
    ucontext_t* uc = p; got_segv = sig;
    printf("segv addr=%p rip_set=%d\n", si->si_addr, uc->uc_mcontext.gregs[REG_RIP] != 0);
    siglongjmp(jb, 1);
}
int main(void) {
    struct sigaction sa; memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_usr1; sa.sa_flags = SA_SIGINFO | SA_RESTART;
    /* same kind of mask as wine's server_block_set */
    sigemptyset(&sa.sa_mask); sigaddset(&sa.sa_mask, SIGHUP); sigaddset(&sa.sa_mask, SIGINT); sigaddset(&sa.sa_mask, SIGQUIT);
    sigaddset(&sa.sa_mask, SIGALRM); sigaddset(&sa.sa_mask, SIGTERM); sigaddset(&sa.sa_mask, SIGCHLD); sigaddset(&sa.sa_mask, SIGRTMIN);
    if (sigaction(SIGUSR1, &sa, NULL)) { perror("sigaction"); return 1; }
    struct sigaction old; sigaction(SIGUSR1, NULL, &old);
    printf("readback handler_ok=%d flags_ok=%d mask_ok=%d\n", old.sa_sigaction == on_usr1, (old.sa_flags & SA_SIGINFO) != 0, sigismember(&old.sa_mask, SIGALRM));
    raise(SIGUSR1);
    printf("usr1=%d\n", got_usr1);
    sa.sa_sigaction = on_segv; sa.sa_flags = SA_SIGINFO; sigaction(SIGSEGV, &sa, NULL);
    if (!sigsetjmp(jb, 1)) { *(volatile int*)0x10 = 1; }
    printf("segv=%d\nSIGOK\n", got_segv);
    return 0;
}
