
inline long read_long() {
  long result;
  asm volatile ("in (0),%[result]" : [result] "=r" (result) : );
  return result;
}

inline long gen_random() {
  long result;
  asm volatile ("in (1),%[result]" : [result] "=r" (result) : );
  return result;
}

inline void write_long(long value) {
  asm volatile ("out %[value],(0)" : : [value] "r" (value) );
}

long* cur_allocator;
long allocator_base;

void init_allocator() {
  cur_allocator = &allocator_base;
}

long* allocate(long num_entries) {
  long* res = cur_allocator;
  cur_allocator = &cur_allocator[num_entries];
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


