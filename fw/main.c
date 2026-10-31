// Dot product of two int8 vectors, first in software and then on mac_accel.
// Prints both results and cycle counts. Returns 0 if they match.

#include <stdint.h>

#define OUT_CHAR   (*(volatile uint32_t *)0x10000000)

#define ACC        0x20000000u
#define CTRL       (*(volatile uint32_t *)(ACC + 0x00))
#define STATUS     (*(volatile uint32_t *)(ACC + 0x04))
#define LEN        (*(volatile uint32_t *)(ACC + 0x08))
#define A_OFF      (*(volatile uint32_t *)(ACC + 0x0C))
#define B_OFF      (*(volatile uint32_t *)(ACC + 0x10))
#define RESULT     (*(volatile uint32_t *)(ACC + 0x14))
#define CYCLES     (*(volatile uint32_t *)(ACC + 0x18))
#define SPAD       ((volatile uint32_t *)(ACC + 0x10000))

#define N 1024

int8_t a[N] __attribute__((aligned(4)));
int8_t b[N] __attribute__((aligned(4)));

static uint32_t cycles(void)
{
    uint32_t c;
    asm volatile ("rdcycle %0" : "=r"(c));
    return c;
}

static void print(const char *s)
{
    while (*s)
        OUT_CHAR = *s++;
}

static void print_num(int32_t v)
{
    char buf[12];
    int n = 0;
    uint32_t u = v;
    if (v < 0) {
        OUT_CHAR = '-';
        u = -u;
    }
    do {
        buf[n++] = '0' + u % 10;
        u /= 10;
    } while (u);
    while (n)
        OUT_CHAR = buf[--n];
}

static int32_t dot(const int8_t *x, const int8_t *y, int n)
{
    int32_t s = 0;
    for (int i = 0; i < n; i++)
        s += x[i] * y[i];
    return s;
}

int main(void)
{
    uint32_t r = 2026;
    for (int i = 0; i < N; i++) {
        r = r * 1664525u + 1013904223u;
        a[i] = r >> 24;
        r = r * 1664525u + 1013904223u;
        b[i] = r >> 24;
    }

    // software
    uint32_t t = cycles();
    int32_t sw = dot(a, b, N);
    uint32_t t_sw = cycles() - t;

    // copy A and B to scratchpad, B right after A
    t = cycles();
    uint32_t *wa = (uint32_t *)a;
    uint32_t *wb = (uint32_t *)b;
    for (int i = 0; i < N / 4; i++) {
        SPAD[i] = wa[i];
        SPAD[N / 4 + i] = wb[i];
    }
    uint32_t t_copy = cycles() - t;

    // accelerator
    t = cycles();
    LEN = N;
    A_OFF = 0;
    B_OFF = N;
    CTRL = 1;
    while ((STATUS & 2) == 0)
        ;
    int32_t hw = RESULT;
    uint32_t t_hw = cycles() - t;

    print("dot product, N="); print_num(N); print("\n");
    print("  software result   : "); print_num(sw); print("  in "); print_num(t_sw); print(" cycles\n");
    print("  accelerator result: "); print_num(hw); print("  in "); print_num(t_hw);
    print(" cycles (engine "); print_num(CYCLES); print(")\n");
    print("  copy into scratchpad: "); print_num(t_copy); print(" cycles\n");
    print("  speed-up (compute only): "); print_num(t_sw / t_hw); print("x\n");
    print("  speed-up (incl. copy):   "); print_num(t_sw / (t_hw + t_copy)); print("x\n");

    if (STATUS & 4) {
        print("FAIL: error flag set\n");
        return 2;
    }
    if (sw != hw) {
        print("FAIL: results differ\n");
        return 1;
    }
    print("PASS\n");
    return 0;
}
