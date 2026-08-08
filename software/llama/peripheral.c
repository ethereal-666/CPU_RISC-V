#include <stdarg.h>
#include "peripheral.h"

/* ==================== Timer ==================== */

#define TIMER_BASE 0xFFFF4000

/*
    | offset | read op               | write op  |
    |--------|-----------------------|-----------|
    | 0x00   | read timer low 32bit  | undefined |
    | 0x08   | read timer high 32bit | undefined |
*/

volatile unsigned int* timer_low =
(volatile unsigned int*)TIMER_BASE;

volatile unsigned int* timer_high =
(volatile unsigned int*)(TIMER_BASE + 0x8);


/* ==================== UART ==================== */

#define UART_BASE 0xFFFF3000

/*
    UART 寄存器：

    | offset | register         |
    |--------|------------------|
    | 0x00   | RX FIFO          |
    | 0x04   | TX FIFO          |
    | 0x08   | status register  |
    | 0x0C   | control register |

    状态寄存器 uart_stat_reg：

    | bit  | 含义                    |
    |------|-------------------------|
    | bit3 | 1：TX FIFO 已满         |
    | bit2 | 1：TX FIFO 为空         |
    | bit1 | 1：RX FIFO 已满         |
    | bit0 | 1：RX FIFO 非空         |

    控制寄存器 uart_ctrl_reg：

    | bit  | 含义                    |
    |------|-------------------------|
    | bit1 | 写 1 清空 RX FIFO       |
    | bit0 | 写 1 清空 TX FIFO       |
*/

volatile unsigned int* uart_rx_fifo =
(volatile unsigned int*)UART_BASE;

volatile unsigned int* uart_tx_fifo =
(volatile unsigned int*)(UART_BASE + 0x4);

volatile unsigned int* uart_stat_reg =
(volatile unsigned int*)(UART_BASE + 0x8);

volatile unsigned int* uart_ctrl_reg =
(volatile unsigned int*)(UART_BASE + 0xC);


/* UART 状态位 */

#define UART_STAT_RX_NOT_EMPTY (1U << 0)
#define UART_STAT_RX_FULL      (1U << 1)
#define UART_STAT_TX_EMPTY     (1U << 2)
#define UART_STAT_TX_FULL      (1U << 3)

/* UART 控制位 */

#define UART_CTRL_CLEAR_TX     (1U << 0)
#define UART_CTRL_CLEAR_RX     (1U << 1)


#define RX_FIFO_SIZE 512

static char rx_buf[RX_FIFO_SIZE];

/* 缓冲区中的有效字符数 */
static int rx_buf_cnt = 0;

/* 当前读取到的缓冲区位置 */
static int rx_buf_ptr = 0;

/* If a terminal sends CRLF, the LF may arrive after CR ended the line. */
static int ignore_lf_after_cr = 0;


/* ==================== UART 基础操作 ==================== */

void uart_init(void)
{
    /*
     * bit1：清空 RX FIFO
     * bit0：清空 TX FIFO
     */
    *uart_ctrl_reg =
        UART_CTRL_CLEAR_RX |
        UART_CTRL_CLEAR_TX;

    /*
     * 清空控制通常使用一个写入脉冲。
     * 清空完成后将控制寄存器恢复为 0。
     */
    *uart_ctrl_reg = 0;

    rx_buf_cnt = 0;
    rx_buf_ptr = 0;
    ignore_lf_after_cr = 0;
}


void uart_putc(char c)
{
    /*
     * status bit3 为 1 时，表示 TX FIFO 已满。
     * 必须等待 TX FIFO 出现空闲位置。
     */
    while ((*uart_stat_reg & UART_STAT_TX_FULL) != 0)
    {
    }

    *uart_tx_fifo = (unsigned int)(unsigned char)c;
}


static char uart_getc(void)
{
    /*
     * 当前软件缓冲区中的字符已经读取完毕，
     * 需要重新从硬件 RX FIFO 读取数据。
     */
    if (rx_buf_ptr >= rx_buf_cnt)
    {
        rx_buf_ptr = 0;
        rx_buf_cnt = 0;

        /*
         * status bit0 为 0 时，表示 RX FIFO 为空。
         * 等待上位机发送数据。
         */
        while ((*uart_stat_reg & UART_STAT_RX_NOT_EMPTY) == 0)
        {
        }

        /*
         * 只要 RX FIFO 非空，并且软件缓冲区未满，
         * 就继续从 RX FIFO 中读取字符。
         */
        while (((*uart_stat_reg & UART_STAT_RX_NOT_EMPTY) != 0) &&
            (rx_buf_cnt < RX_FIFO_SIZE))
        {
            rx_buf[rx_buf_cnt++] =
                (char)(*uart_rx_fifo & 0xFFU);
        }
    }

    return rx_buf[rx_buf_ptr++];
}


/* ==================== Timer 操作 ==================== */

time_l get_time(void)
{
    unsigned int high_before;
    unsigned int high_after;
    unsigned int low;

    do
    {
        high_before = *timer_high;
        low = *timer_low;
        high_after = *timer_high;
    }
    while (high_before != high_after);

    return ((time_l)high_after << 32) | (time_l)low;
}


/* ==================== printf 实现 ==================== */

static void print_char(char c)
{
    if (c == '\n')
    {
        uart_putc('\r');
    }

    uart_putc(c);
}


static void print_string(const char* s)
{
    if (s == 0)
    {
        print_string("(null)");
        return;
    }

    while (*s)
    {
        print_char(*s++);
    }
}


static void print_number(
    unsigned int num,
    unsigned int base,
    int is_signed
)
{
    char buffer[32];
    char* ptr = buffer;

    static const char digits[] =
        "0123456789ABCDEF";

    if (base < 2 || base > 16)
    {
        return;
    }

    if (is_signed && (int)num < 0)
    {
        print_char('-');

        /*
         * 使用无符号运算处理 INT_MIN，
         * 避免直接对有符号最小值取负产生溢出。
         */
        num = 0U - num;
    }

    do
    {
        *ptr++ = digits[num % base];
        num /= base;
    } while (num > 0);

    while (ptr > buffer)
    {
        print_char(*--ptr);
    }
}


static void print_float(float num, int precision)
{
    if (precision < 0 || precision > 6)
    {
        precision = 6;
    }

    if (num < 0)
    {
        print_char('-');
        num = -num;
    }

    float tmp = num * 1000000.0f;

    unsigned int integer_part =
        (unsigned int)num;

    unsigned int fractional_part =
        (unsigned int)tmp -
        integer_part * 1000000U;

    print_number(integer_part, 10, 0);

    if (precision > 0 || fractional_part > 0)
    {
        print_char('.');
    }

    char fractional_str[7] = { '\0' };

    for (int i = 5; i >= 0; i--)
    {
        fractional_str[i] =
            (char)('0' + fractional_part % 10U);

        fractional_part /= 10U;
    }

    fractional_str[precision] = '\0';

    print_string(fractional_str);
}


int vprintf(const char* format, va_list ap)
{
    const char* p = format;
    char c;

    while ((c = *p++) != '\0')
    {
        if (c != '%')
        {
            print_char(c);
            continue;
        }

        c = *p++;

        switch (c)
        {
        case 'c':
        {
            print_char((char)va_arg(ap, int));
            break;
        }

        case 's':
        {
            print_string(va_arg(ap, char*));
            break;
        }

        case 'd':
        {
            print_number(
                (unsigned int)va_arg(ap, int),
                10,
                1
            );
            break;
        }

        case 'u':
        {
            print_number(
                va_arg(ap, unsigned int),
                10,
                0
            );
            break;
        }

        case 'x':
        {
            print_number(
                va_arg(ap, unsigned int),
                16,
                0
            );
            break;
        }

        case 'f':
        {
            /*
             * 可变参数中的 float 会提升为 double。
             */
            print_float(
                (float)va_arg(ap, double),
                6
            );
            break;
        }

        case '%':
        {
            print_char('%');
            break;
        }

        case '\0':
        {
            /*
             * format 以单独的 '%' 结尾。
             */
            print_char('%');
            return 0;
        }

        default:
        {
            print_char('%');
            print_char(c);
            break;
        }
        }
    }

    return 0;
}


int printf(const char* format, ...)
{
    va_list ap;

    va_start(ap, format);
    int ret = vprintf(format, ap);
    va_end(ap);

    return ret;
}


/* ==================== 输入行读取 ==================== */

int uart_readline(char* buf, int max_len)
{
    char* p = buf;
    char c;
    int overflow = 0;

    if (buf == 0 || max_len <= 0)
    {
        return -1;
    }

    while (1)
    {
        c = uart_getc();

        if (ignore_lf_after_cr)
        {
            ignore_lf_after_cr = 0;
            if (c == '\n')
            {
                continue;
            }
        }

        if (c == '\r' || c == '\n')
        {
            if (c == '\r')
            {
                ignore_lf_after_cr = 1;
            }
            print_char('\n');
            *p = '\0';
            return overflow ? -2 : (int)(p - buf);
        }
        else if ((c == '\b' || c == 127) && p > buf)
        {
            /*
             * 删除缓冲区中的最后一个字符。
             */
            p--;

            /*
             * 在终端中擦除已经回显的字符。
             */
            print_char('\b');
            print_char(' ');
            print_char('\b');
        }
        else if ((p - buf) < (max_len - 1))
        {
            /*
             * 回显输入字符。
             */
            print_char(c);

            *p++ = c;
        }
        else
        {
            overflow = 1;
        }
    }
}


/* ==================== 字符串转整数 ==================== */

static int str2int(const char** s)
{
    const char* p = *s;

    int val = 0;
    int sign = 1;

    while (*p == ' ' || *p == '\t')
    {
        p++;
    }

    if (*p == '-')
    {
        sign = -1;
        p++;
    }
    else if (*p == '+')
    {
        p++;
    }

    while (*p >= '0' && *p <= '9')
    {
        /*
         * val * 10：
         * val * 8 + val * 2
         */
        val =
            (val << 3) +
            (val << 1) +
            (*p - '0');

        p++;
    }

    *s = p;

    return val * sign;
}


/* ==================== scanf 实现 ==================== */

int vscanf(const char* format, va_list ap)
{
    static char input_buffer[SCAN_BUF_SIZE];
    static char* input_ptr = 0;

    /*
     * 第一次调用时 input_ptr 为 NULL。
     * 或者上一行数据已读完时，重新读取一行。
     */
    if (input_ptr == 0 || *input_ptr == '\0')
    {
        if (uart_readline(input_buffer, SCAN_BUF_SIZE) < 0)
        {
            input_buffer[0] = '\0';
            input_ptr = input_buffer;
            return 0;
        }
        input_ptr = input_buffer;
    }

    /*
     * 跳过输入开头的空白字符。
     */
    while (*input_ptr == ' ' ||
        *input_ptr == '\t' ||
        *input_ptr == '\n' ||
        *input_ptr == '\r')
    {
        input_ptr++;
    }

    const char* p_fmt = format;
    int count = 0;

    while (*p_fmt)
    {
        if (*p_fmt == '%')
        {
            p_fmt++;

            while (*input_ptr == ' ' ||
                *input_ptr == '\t' ||
                *input_ptr == '\n' ||
                *input_ptr == '\r')
            {
                input_ptr++;
            }

            if (*input_ptr == '\0')
            {
                break;
            }

            switch (*p_fmt)
            {
            case 'd':
            {
                int* val = va_arg(ap, int*);

                *val = str2int(
                    (const char**)&input_ptr
                );

                count++;
                break;
            }

            case 'c':
            {
                char* c = va_arg(ap, char*);

                *c = *input_ptr++;

                count++;
                break;
            }

            case 's':
            {
                char* s = va_arg(ap, char*);

                /*
                 * %s 应在任意空白字符处停止。
                 */
                while (*input_ptr != '\0' &&
                    *input_ptr != ' ' &&
                    *input_ptr != '\t' &&
                    *input_ptr != '\n' &&
                    *input_ptr != '\r')
                {
                    *s++ = *input_ptr++;
                }

                *s = '\0';

                count++;
                break;
            }

            case '%':
            {
                if (*input_ptr != '%')
                {
                    return count;
                }

                input_ptr++;
                break;
            }

            default:
            {
                return count;
            }
            }
        }
        else if (*p_fmt == ' ' ||
            *p_fmt == '\t' ||
            *p_fmt == '\n')
        {
            /*
             * format 中的空白字符可以匹配输入中的任意数量空白。
             */
            while (*input_ptr == ' ' ||
                *input_ptr == '\t' ||
                *input_ptr == '\n' ||
                *input_ptr == '\r')
            {
                input_ptr++;
            }
        }
        else
        {
            /*
             * 普通字符需要与输入完全一致。
             */
            if (*p_fmt != *input_ptr)
            {
                break;
            }

            input_ptr++;
        }

        p_fmt++;
    }

    return count;
}


int scanf(const char* format, ...)
{
    va_list ap;

    va_start(ap, format);
    int ret = vscanf(format, ap);
    va_end(ap);

    return ret;
}
