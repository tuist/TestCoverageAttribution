#include "Classify.h"

int classify(int value) {
    if (value < 0) return -1;
    if (value == 0) return 0;
    return 1;
}

int sum(int count) {
    int total = 0;
    for (int i = 1; i <= count; i++) total += i;
    return total;
}
