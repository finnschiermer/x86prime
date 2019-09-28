#include "io.c"
#include "alloc.c"

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

// main program using I/O
void run() {
  init_allocator();
  long num_entries = read_long();
  long* p = get_random_array(num_entries);
  sort(num_entries, p);
  print_array(num_entries, p);
}

// main program using command line argument
void run2() {
  init_allocator();
  // we could check number of arguments... 
  // but we have no way of reporting an error anyway.
  // so let's just assume it's there:
  long num_entries = get_argv()[0];
  long* p = get_random_array(num_entries);
  sort(num_entries, p);
  print_array(num_entries, p);
}
