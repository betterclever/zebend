#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
static inline uint32_t xs(uint32_t x){ x^=x<<13; x^=x>>17; x^=x<<5; return x; }
static uint32_t run(uint64_t n, uint32_t x){ uint32_t acc=0; while(n--){ acc+=x; x=xs(x);} return acc; }
typedef struct { uint32_t seed; uint64_t n; uint32_t out; } job;
static job js[64]; static int T;
// thread t handles chunks t, t+T, t+2T, ... (static interleaved split, no waves)
static void* work(void* p){ int t=(int)(intptr_t)p; for(int i=t;i<64;i+=T) js[i].out=run(js[i].n, js[i].seed+1); return 0; }
int main(int c, char** v){
  int threads = c>1 ? atoi(v[1]) : 1; const int chunks=64; const uint64_t n=4194304;
  for(int i=0;i<chunks;i++){ js[i].seed=i; js[i].n=n; }
  // seeds follow the Bend tree: leaf i (left-to-right) has seed i
  uint32_t total=0; T=threads; pthread_t t[64];
  for(int i=0;i<threads;i++) pthread_create(&t[i],0,work,(void*)(intptr_t)i);
  for(int i=0;i<threads;i++) pthread_join(t[i],0);
  for(int i=0;i<chunks;i++) total+=js[i].out;
  printf("%u\n", total);
}
