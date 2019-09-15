
long* cur_allocator;
long allocator_base;

void init_allocator() {
  cur_allocator = &allocator_base;
}

long* allocate(long num_entries) {
  long* res = cur_allocator;
  cur_allocator = &cur_allocator[num_entries];
  return res;
}
