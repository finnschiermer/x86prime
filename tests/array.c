#include <stdio.h>
#include <stdlib.h>

int main() {
  int a[] = {1, 1, 0, 0, 0, 0, 0, 0};
  for (int i = 2; i < sizeof(a); i++) {
    a[i] = a[i-1] + a[i-2];
  }
  return 0;
}
