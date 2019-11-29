
long* cur_allocator;


void init_allocator() {
  cur_allocator = (long*) 0x30000000;
}

long* allocate(long num_entries) {
  long* res = cur_allocator;
  cur_allocator = res + num_entries;
  return res;
}
