import Base

def DNS.resolve(host: String) -> IO(Result<&1, &1, U32 & String, String>):
  import "./dns.c"
  import "./dns.js"

def main() -> IO(Unit):
  do IO<Unit>:
    ips : String <- IO.try(String, DNS.resolve("mainnet.seeder.zfnd.org"))
    IO.print("mainnet.seeder.zfnd.org -> " ++ ips)
