// Clock.unix() -> seconds since the Unix epoch (the P2P version timestamp).
#include <time.h>

Term clock_unix_run(Env e, Term* f, IoWork* w) {
  return (Term)(uint32_t)time(NULL);
}

static void __attribute__((constructor)) clock_unix_use(void) {
  io_eff(CID(Clock.unix), clock_unix_run);
}
