// DNS.resolve(host) -> comma-separated IPv4 addresses (TCP.connect takes IPv4 literals).
// getaddrinfo blocks, so it runs on an IO helper thread via io_work.
#include <netdb.h>
#include <arpa/inet.h>

static void dns_resolve_call(IoWork* w) {
  struct addrinfo hints = { 0 }, *res = NULL;
  hints.ai_family   = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  int rc = getaddrinfo((const char*)w->data, NULL, &hints, &res);
  char* out = malloc(4096);
  size_t n  = 0;
  out[0]    = 0;
  if (rc == 0) {
    for (struct addrinfo* a = res; a != NULL && n < 4000; a = a->ai_next) {
      char ip[INET_ADDRSTRLEN];
      struct sockaddr_in* sin = (struct sockaddr_in*)a->ai_addr;
      if (inet_ntop(AF_INET, &sin->sin_addr, ip, sizeof ip) == NULL) continue;
      if (strstr(out, ip) != NULL) continue;  // getaddrinfo repeats per protocol
      n += (size_t)snprintf(out + n, 4096 - n, "%s%s", n ? "," : "", ip);
    }
    freeaddrinfo(res);
    w->code = 0;
  } else {
    w->code = EHOSTUNREACH;
  }
  free(w->data);
  w->data = out;
  w->size = n;
}

static Term dns_resolve_pack(Env e, IoWork* w) {
  Term r = io_res(e, w, io_str(e, w->data, w->size));
  free(w->data);
  return r;
}

Term dns_resolve_run(Env e, Term* f, IoWork* w) {
  w->data = io_cstr(e, f[0], &w->size);
  return io_work(w, dns_resolve_call, dns_resolve_pack);
}

static void __attribute__((constructor)) dns_resolve_use(void) {
  io_eff(CID(DNS.resolve), dns_resolve_run);
}
