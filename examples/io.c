/*
  Basic IO functions
*/

long read_long() {
  long read_addr = 0x10000000ULL;
  return * (volatile long *) read_addr;
}

long gen_random() {
  long read_addr = 0x10000001ULL;
  return * (volatile long *) read_addr;
}

void write_long(long value) {
  long write_addr = 0x10000002ULL;
  * (volatile long *) write_addr = value;
}

// We also support passing an argument vector of quads
long get_argc() {
  long read_addr = 0x20000000ULL;
  return * (volatile long *) read_addr;
}

long* get_argv() {
  long read_addr = 0x20000008ULL;
  return (long*) read_addr;
}


