#define qsort_r box64sim_qsort_r
#include <sys/sem.h>
union semun { int val; struct semid_ds* buf; unsigned short* array; struct seminfo* __buf; };
