
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

long* get_random_array(long num_entries) {
  long* p = allocate(num_entries);
  for (long i = 0; i < num_entries; ++i) {
    p[i] = gen_random();
  }
  return p;
}

void sort(long num_elem, long array[]) {

  for (long i = 0; i < num_elem; ++i) {
    for (long j = i + 1; j < num_elem; j++) {
      if (array[i] > array[j]) {
        long tmp = array[i];
        array[i] = array[j];
        array[j] = tmp;
      }
    }
  }
}

void print_array(long num_elem, long array[]) {

  for (long i = 0; i < num_elem; ++i) {
    write_long(array[i]);
  }

}

void run() {
  init_allocator();
  long num_entries = read_long();
  long* p = get_random_array(num_entries);
  sort(num_entries, p);
  print_array(num_entries, p);
}


