#ifndef PERIPHERAL_H
#define PERIPHERAL_H

typedef unsigned long long time_l;

#define CPU_CLK_FREQ 50     // MHz
#define CLKS_PER_SEC (1000000 * CPU_CLK_FREQ)

time_l get_time(void);

void uart_init();

/* Returns length, -1 for invalid arguments, or -2 when the line is too long. */
int uart_readline(char *buf, int max_len);

int printf(const char *format, ...);

#define SCAN_BUF_SIZE 128
int scanf(const char *format, ...);

#endif
