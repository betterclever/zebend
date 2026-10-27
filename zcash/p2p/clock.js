function clock_unix() {
  return Math.floor(Date.now() / 1000);
}

io_eff(CID(Clock.unix), clock_unix);
