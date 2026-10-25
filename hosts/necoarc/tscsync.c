/* tscsync — measure per-CPU TSC offsets and, with --apply, write IA32_TSC (MSR 0x10)
 * on out-of-sync CPUs so all cores agree. Workaround for firmware that leaves the boot
 * CPU's TSC unsynchronised (Lenovo Legion Slim 5 14APH8 / AMD Phoenix).
 *
 * Measurement: symmetric ping-pong between two pinned threads (like the kernel's
 * check_tsc_warp); off = TSC(target) - TSC(ref); signal latency cancels out.
 * Reference: the CPU closest to the median offset, i.e. the majority cluster.
 * Write: from a thread pinned to the target CPU via /dev/cpu/N/msr; the syscall
 * latency is learned from the residual and compensated on the next pass.
 *
 * Exit status: 0 all CPUs within tolerance, 1 sync failed / still out of sync, 2 usage.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sched.h>
#include <pthread.h>
#include <stdatomic.h>
#include <x86intrin.h>

#define MSR_IA32_TSC 0x10
#define ROUNDS 401
#define TARGET 200LL         /* cycles: keep correcting until within this (~50 ns) ... */
#define TOLERANCE 1000LL     /* ... but only report failure above this (~260 ns) */
#define MAX_PASSES 10        /* write jitter is ~100-300 cycles, so a few passes may be needed */

static int ncpu;
static double tsc_hz = 3.792e9;

/* TSC rate for the "seconds" display column only: rdtsc vs CLOCK_MONOTONIC over 50 ms.
   No external commands, works in an initramfs. Accuracy ~1e-5, plenty for display. */
static void calibrate_tsc_hz(void){
    struct timespec a,b; unsigned aux;
    clock_gettime(CLOCK_MONOTONIC,&a); uint64_t t0=__rdtscp(&aux);
    usleep(50000);
    uint64_t t1=__rdtscp(&aux); clock_gettime(CLOCK_MONOTONIC,&b);
    double dt=(b.tv_sec-a.tv_sec)+(b.tv_nsec-a.tv_nsec)*1e-9;
    if (dt>0.01) tsc_hz=(t1-t0)/dt;
}

static void pin(int cpu){
    cpu_set_t s; CPU_ZERO(&s); CPU_SET(cpu,&s);
    if (sched_setaffinity(0,sizeof s,&s)) { perror("sched_setaffinity"); exit(1); }
    sched_yield();
}
static inline uint64_t stamp(void){ unsigned a; return __rdtscp(&a); }

static _Atomic int go, ack;
static uint64_t B1, B2;
static int tgt_cpu;

static void *target_thread(void *arg){
    (void)arg; pin(tgt_cpu);
    for (int r=1; r<=ROUNDS; r++){
        while (atomic_load(&go)!=r) __builtin_ia32_pause();
        B1 = stamp(); B2 = stamp();
        atomic_store(&ack, r);
    }
    return NULL;
}
static int cmpll(const void *a,const void *b){ long long x=*(const long long*)a,y=*(const long long*)b; return (x>y)-(x<y); }

/* TSC(target) - TSC(ref), median of ROUNDS */
static long long measure(int ref, int target){
    if (ref==target) return 0;
    long long samples[ROUNDS];
    tgt_cpu = target; atomic_store(&go,0); atomic_store(&ack,0);
    pin(ref);
    pthread_t th; pthread_create(&th,NULL,target_thread,NULL);
    usleep(2000);
    for (int r=1; r<=ROUNDS; r++){
        uint64_t A1 = stamp();
        atomic_store(&go, r);
        while (atomic_load(&ack)!=r) __builtin_ia32_pause();
        uint64_t A2 = stamp();
        samples[r-1] = ((long long)(B1-A1) - (long long)(A2-B2))/2;
    }
    pthread_join(th,NULL);
    qsort(samples,ROUNDS,sizeof *samples,cmpll);
    return samples[ROUNDS/2];
}

struct wjob { int cpu; long long delta; int rc; };
static void *write_thread(void *arg){
    struct wjob *j = arg; pin(j->cpu);
    char path[64]; snprintf(path,sizeof path,"/dev/cpu/%d/msr",j->cpu);
    int fd = open(path,O_WRONLY);
    if (fd<0){ fprintf(stderr,"open %s: %s (is the msr module loaded?)\n",path,strerror(errno)); j->rc=-1; return NULL; }
    uint64_t val = stamp() + (uint64_t)j->delta;
    ssize_t n = pwrite(fd,&val,8,MSR_IA32_TSC);
    close(fd);
    j->rc = (n==8)?0:-1;
    if (j->rc) fprintf(stderr,"wrmsr IA32_TSC on cpu%d: %s\n",j->cpu,strerror(errno));
    return NULL;
}
static int write_tsc_delta(int cpu, long long delta){
    struct wjob j={cpu,delta,0}; pthread_t th;
    pthread_create(&th,NULL,write_thread,&j); pthread_join(th,NULL);
    return j.rc;
}

/* pick the reference: CPU whose offset (vs cpu0) is closest to the median */
static int choose_ref(void){
    long long off[ncpu], sorted[ncpu];
    for (int c=0;c<ncpu;c++) off[c]=sorted[c]=measure(0,c);
    qsort(sorted,ncpu,sizeof *sorted,cmpll);
    long long med = sorted[ncpu/2]; int best=0; long long bd=-1;
    for (int c=0;c<ncpu;c++){ long long d=llabs(off[c]-med); if (bd<0||d<bd){bd=d;best=c;} }
    return best;
}

static int report(int ref){
    int bad=0;
    printf("%4s %18s %14s\n","cpu","TSC - TSC(ref)","seconds");
    for (int c=0;c<ncpu;c++){
        long long off = measure(ref,c);
        int out = llabs(off)>TOLERANCE; bad+=out;
        printf("%4d %18lld %14.6f%s%s\n",c,off,off/tsc_hz,c==ref?"  (ref)":"",out?"  <-- out of sync":"");
    }
    return bad;
}

int main(int argc,char **argv){
    int apply = argc>1 && !strcmp(argv[1],"--apply");
    int quiet = argc>2 && !strcmp(argv[2],"--quiet");
    if (!apply && !(argc>1 && !strcmp(argv[1],"--measure"))){
        fprintf(stderr,"usage: %s --measure | --apply [--quiet]\n",argv[0]); return 2;
    }
    ncpu = sysconf(_SC_NPROCESSORS_ONLN);
    calibrate_tsc_hz();
    int ref = choose_ref();

    if (!quiet){ printf("== before (ref = cpu%d, target %lld / tolerance %lld cycles)\n",ref,TARGET,TOLERANCE); }
    int bad = quiet ? 0 : report(ref);
    if (!apply) return bad?1:0;

    if (!quiet) printf("\n== applying\n");
    for (int c=0;c<ncpu;c++){
        if (c==ref) continue;
        long long comp = 0;
        long long off = measure(ref,c);
        if (llabs(off)<=TARGET) continue;               /* already good, don't touch */
        int pass;
        for (pass=1; pass<=MAX_PASSES; pass++){
            long long delta = -off + comp;
            printf("cpu%d pass %d: off=%lld  writing TSC += %lld (comp %lld)\n",c,pass,off,delta,comp);
            if (write_tsc_delta(c,delta)) return 1;
            long long off2 = measure(ref,c);
            comp -= off2;                                /* learn the write latency from the residual */
            off = off2;
            if (llabs(off)<=TARGET) break;
        }
        if (llabs(off)>TOLERANCE){ printf("cpu%d: FAILED, residual %lld cycles after %d passes\n",c,off,pass); return 1; }
        printf("cpu%d: in sync (%lld cycles) after %d pass(es)\n",c,off,pass>MAX_PASSES?MAX_PASSES:pass);
    }
    if (!quiet){ printf("\n== after\n"); return report(ref)?1:0; }
    for (int c=0;c<ncpu;c++) if (llabs(measure(ref,c))>TOLERANCE) return 1;
    return 0;
}
