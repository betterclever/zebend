// DNS needs the native build (getaddrinfo); under the JS runner it reports ENOSYS.
function dns_resolve(host) {
  return io_fail(38);
}

io_eff(CID(DNS.resolve), dns_resolve);
