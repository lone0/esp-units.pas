#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>

#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "driver/spi_master.h"
#include "esp_err.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_st7789.h"
#include "esp_log.h"
#include "esp_rom_sys.h"
#include "esp_vfs.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

/* Logical landscape space after esp_lcd_panel_swap_xy(panel, true): with
 * MADCTL MV=1 the panel transposes its window addressing, so draw_bitmap x
 * spans the 480-px horizontal and y the 320-px vertical. */
#define LCD_WIDTH 480
#define LCD_HEIGHT 320
#define LCD_SPI_HOST SPI3_HOST

#define LCD_MOSI_GPIO 1
#define LCD_MISO_GPIO 2
#define LCD_SCLK_GPIO 5
#define LCD_DC_GPIO 3
#define LCD_BACKLIGHT_GPIO 6

#define I2C_SDA_GPIO 8
#define I2C_SCL_GPIO 7
#define AXP2101_ADDRESS 0x34
#define TCA9554_ADDRESS 0x20

#define CONSOLE_COLUMNS (LCD_WIDTH / (CONSOLE_FONT_WIDTH * CONSOLE_SCALE))
#define CONSOLE_ROWS (LCD_HEIGHT / (CONSOLE_FONT_HEIGHT * CONSOLE_SCALE))
#define CONSOLE_FONT_WIDTH 6
#define CONSOLE_FONT_HEIGHT 8
#define CONSOLE_SCALE 2
#define CONSOLE_QUEUE_LENGTH 2048
#define CONSOLE_WRITE_WAIT_TICKS pdMS_TO_TICKS(20)
#define CONSOLE_RENDER_BATCH 128

static const char *const TAG = "waveshare_lcd";
static esp_lcd_panel_handle_t panel;
static esp_lcd_panel_io_handle_t panel_io;

/* Full-frame double buffering: esp_lcd_panel_io_tx_color is asynchronous
 * (spi_device_queue_trans), so reusing a per-row line buffer corrupted every
 * row with the next row's pixels while its DMA was still in flight. Each
 * refresh now builds one complete 480x320 frame and never touches the buffer
 * of a transfer that has not completed (completion is tracked through the
 * on_color_trans_done callback). */
static uint16_t *console_frame[2];
static int console_frame_index;
static SemaphoreHandle_t console_frame_done;
static StaticQueue_t console_queue_buffer;
static uint8_t console_queue_storage[CONSOLE_QUEUE_LENGTH];
static StaticTask_t console_task_buffer;
static StackType_t console_task_stack[4096];
static QueueHandle_t console_queue;
static TaskHandle_t console_task;
static portMUX_TYPE console_drop_lock = portMUX_INITIALIZER_UNLOCKED;
static uint32_t console_dropped_bytes;
static uint32_t console_newline_count;
static uint32_t console_scroll_count;
static char console_top_row_snapshot[CONSOLE_COLUMNS];

#define RETURN_IF_ERROR(expression, message) \
    do { \
        esp_err_t error = (expression); \
        if (error != ESP_OK) { \
            ESP_LOGE(TAG, "%s: %s", message, esp_err_to_name(error)); \
            return error; \
        } \
    } while (0)

static esp_err_t i2c_write_register(i2c_master_dev_handle_t device, uint8_t register_address,
                                    uint8_t value)
{
    const uint8_t buffer[] = {register_address, value};
    return i2c_master_transmit(device, buffer, sizeof(buffer), -1);
}

static esp_err_t initialize_power(i2c_master_bus_handle_t *bus)
{
    i2c_master_bus_config_t config = {
        .i2c_port = I2C_NUM_0,
        .sda_io_num = I2C_SDA_GPIO,
        .scl_io_num = I2C_SCL_GPIO,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .intr_priority = 0,
        .trans_queue_depth = 0,
        .flags.enable_internal_pullup = true,
    };
    RETURN_IF_ERROR(i2c_new_master_bus(&config, bus), "create I2C bus");

    i2c_device_config_t axp_config = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = AXP2101_ADDRESS,
        .scl_speed_hz = 100000,
    };
    i2c_master_dev_handle_t axp;
    RETURN_IF_ERROR(i2c_master_bus_add_device(*bus, &axp_config, &axp), "add AXP2101 device");

    i2c_device_config_t expander_config = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = TCA9554_ADDRESS,
        .scl_speed_hz = 100000,
    };
    i2c_master_dev_handle_t expander;
    RETURN_IF_ERROR(i2c_master_bus_add_device(*bus, &expander_config, &expander), "add IO expander device");

    RETURN_IF_ERROR(i2c_write_register(axp, 0x80, 0x01), "disable unused DC rails");
    RETURN_IF_ERROR(i2c_write_register(axp, 0x90, 0x00), "disable unused LDO rails");
    RETURN_IF_ERROR(i2c_write_register(axp, 0x91, 0x00), "disable unused extended LDO rails");
    RETURN_IF_ERROR(i2c_write_register(axp, 0x82, 18), "set DC1 voltage");
    RETURN_IF_ERROR(i2c_write_register(axp, 0x92, 28), "set ALDO1 voltage");
    RETURN_IF_ERROR(i2c_write_register(axp, 0x96, 10), "set BLDO1 voltage");
    RETURN_IF_ERROR(i2c_write_register(axp, 0x97, 23), "set BLDO2 voltage");
    RETURN_IF_ERROR(i2c_write_register(axp, 0x90, 0x31), "enable display power rails");

    RETURN_IF_ERROR(i2c_write_register(expander, 0x03, 0xfc), "configure IO expander");
    RETURN_IF_ERROR(i2c_write_register(expander, 0x01, 0x00), "reset IO expander outputs");
    esp_rom_delay_us(100000);
    RETURN_IF_ERROR(i2c_write_register(expander, 0x01, 0x02), "release display power");
    esp_rom_delay_us(100000);
    return ESP_OK;
}

static esp_err_t send_panel_command(uint8_t command, const uint8_t *data, size_t data_size)
{
    return esp_lcd_panel_io_tx_param(panel_io, command, data, data_size);
}

static bool console_frame_trans_done(esp_lcd_panel_io_handle_t io, esp_lcd_panel_io_event_data_t *edata,
                                     void *ctx)
{
    (void)io;
    (void)edata;
    BaseType_t yield = pdFALSE;
    xSemaphoreGiveFromISR(console_frame_done, &yield);
    return yield == pdTRUE;
}

static esp_err_t initialize_panel(void)
{
    spi_bus_config_t bus_config = {
        .mosi_io_num = LCD_MOSI_GPIO,
        .miso_io_num = LCD_MISO_GPIO,
        .sclk_io_num = LCD_SCLK_GPIO,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = LCD_WIDTH * 16 * sizeof(uint16_t),
    };
    RETURN_IF_ERROR(spi_bus_initialize(LCD_SPI_HOST, &bus_config, SPI_DMA_CH_AUTO), "initialize LCD SPI bus");

    esp_lcd_panel_io_spi_config_t io_config = {
        .cs_gpio_num = -1,
        .dc_gpio_num = LCD_DC_GPIO,
        .spi_mode = 0,
        .pclk_hz = 40 * 1000 * 1000,
        .trans_queue_depth = 10,
        .lcd_cmd_bits = 8,
        .lcd_param_bits = 8,
        .on_color_trans_done = console_frame_trans_done,
        .flags = {
            .psram_dma_direct = 1,
        },
    };
    RETURN_IF_ERROR(esp_lcd_new_panel_io_spi(LCD_SPI_HOST, &io_config, &panel_io), "create LCD SPI IO");

    esp_lcd_panel_dev_config_t panel_config = {
        .reset_gpio_num = -1,
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_BGR,
        .bits_per_pixel = 16,
    };
    RETURN_IF_ERROR(esp_lcd_new_panel_st7789(panel_io, &panel_config, &panel), "create ST7796-compatible panel");
    RETURN_IF_ERROR(esp_lcd_panel_reset(panel), "reset panel");
    RETURN_IF_ERROR(esp_lcd_panel_init(panel), "initialize panel");

    static const uint8_t f0_c3[] = {0xc3};
    static const uint8_t f0_96[] = {0x96};
    static const uint8_t b4[] = {0x01};
    static const uint8_t b7[] = {0xc6};
    static const uint8_t c0[] = {0x80, 0x45};
    static const uint8_t c1[] = {0x13};
    static const uint8_t c2[] = {0xa7};
    static const uint8_t c5[] = {0x0a};
    static const uint8_t e8[] = {0x40, 0x8a, 0x00, 0x00, 0x29, 0x19, 0xa5, 0x33};
    static const uint8_t e0[] = {0xd0, 0x08, 0x0f, 0x06, 0x06, 0x33, 0x30, 0x33, 0x47, 0x17, 0x13, 0x13, 0x2b, 0x31};
    static const uint8_t e1[] = {0xd0, 0x0a, 0x11, 0x0b, 0x09, 0x07, 0x2f, 0x33, 0x47, 0x38, 0x15, 0x16, 0x2c, 0x32};
    static const uint8_t f0_3c[] = {0x3c};
    static const uint8_t f0_69[] = {0x69};

    RETURN_IF_ERROR(send_panel_command(0xf0, f0_c3, sizeof(f0_c3)), "configure panel command set");
    RETURN_IF_ERROR(send_panel_command(0xf0, f0_96, sizeof(f0_96)), "unlock panel command set");
    RETURN_IF_ERROR(send_panel_command(0xb4, b4, sizeof(b4)), "configure panel display cycle");
    RETURN_IF_ERROR(send_panel_command(0xb7, b7, sizeof(b7)), "configure panel entry mode");
    RETURN_IF_ERROR(send_panel_command(0xc0, c0, sizeof(c0)), "configure panel power");
    RETURN_IF_ERROR(send_panel_command(0xc1, c1, sizeof(c1)), "configure panel VCOM");
    RETURN_IF_ERROR(send_panel_command(0xc2, c2, sizeof(c2)), "configure panel power control");
    RETURN_IF_ERROR(send_panel_command(0xc5, c5, sizeof(c5)), "configure panel frame rate");
    RETURN_IF_ERROR(send_panel_command(0xe8, e8, sizeof(e8)), "configure panel timing");
    RETURN_IF_ERROR(send_panel_command(0xe0, e0, sizeof(e0)), "configure panel positive gamma");
    RETURN_IF_ERROR(send_panel_command(0xe1, e1, sizeof(e1)), "configure panel negative gamma");
    RETURN_IF_ERROR(send_panel_command(0xf0, f0_3c, sizeof(f0_3c)), "lock panel command set");
    RETURN_IF_ERROR(send_panel_command(0xf0, f0_69, sizeof(f0_69)), "lock panel command set");
    RETURN_IF_ERROR(send_panel_command(0x21, NULL, 0), "invert panel colors");
    RETURN_IF_ERROR(send_panel_command(0x29, NULL, 0), "enable panel display");
    /* Landscape needs MADCTL MV transposition on this glass (native portrait
     * 320x480; the no-MV register set renders portrait and garbles data). */
    RETURN_IF_ERROR(esp_lcd_panel_swap_xy(panel, true), "rotate panel to landscape");
    RETURN_IF_ERROR(esp_lcd_panel_mirror(panel, false, false), "set panel orientation");

    gpio_config_t backlight_config = {
        .pin_bit_mask = 1ULL << LCD_BACKLIGHT_GPIO,
        .mode = GPIO_MODE_OUTPUT,
    };
    RETURN_IF_ERROR(gpio_config(&backlight_config), "configure backlight");
    RETURN_IF_ERROR(gpio_set_level(LCD_BACKLIGHT_GPIO, 1), "enable backlight");
    return ESP_OK;
}

static const uint8_t *glyph_rows(char character)
{
    static const uint8_t blank[7] = {0};
    static const uint8_t unknown[7] = {31, 17, 21, 21, 21, 17, 31};
    static const uint8_t digits[][7] = {
        {14, 17, 19, 21, 25, 17, 14}, {4, 12, 4, 4, 4, 4, 14},
        {14, 17, 1, 2, 4, 8, 31}, {30, 1, 1, 14, 1, 1, 30},
        {2, 6, 10, 18, 31, 2, 2}, {31, 16, 30, 1, 1, 17, 14},
        {6, 8, 16, 30, 17, 17, 14}, {31, 1, 2, 4, 8, 8, 8},
        {14, 17, 17, 14, 17, 17, 14}, {14, 17, 17, 15, 1, 2, 12},
    };
    static const uint8_t letters[][7] = {
        {14, 17, 17, 31, 17, 17, 17}, {30, 17, 17, 30, 17, 17, 30},
        {14, 17, 16, 16, 16, 17, 14}, {30, 17, 17, 17, 17, 17, 30},
        {31, 16, 16, 30, 16, 16, 31}, {31, 16, 16, 30, 16, 16, 16},
        {14, 17, 16, 23, 17, 17, 15}, {17, 17, 17, 31, 17, 17, 17},
        {14, 4, 4, 4, 4, 4, 14}, {1, 1, 1, 1, 17, 17, 14},
        {17, 18, 20, 24, 20, 18, 17}, {16, 16, 16, 16, 16, 16, 31},
        {17, 27, 21, 21, 17, 17, 17}, {17, 25, 21, 19, 17, 17, 17},
        {14, 17, 17, 17, 17, 17, 14}, {30, 17, 17, 30, 16, 16, 16},
        {14, 17, 17, 17, 21, 18, 13}, {30, 17, 17, 30, 20, 18, 17},
        {15, 16, 16, 14, 1, 1, 30}, {31, 4, 4, 4, 4, 4, 4},
        {17, 17, 17, 17, 17, 17, 14}, {17, 17, 17, 17, 17, 10, 4},
        {17, 17, 17, 21, 21, 21, 10}, {17, 17, 10, 4, 10, 17, 17},
        {17, 17, 10, 4, 4, 4, 4}, {31, 1, 2, 4, 8, 16, 31},
    };
    static const uint8_t exclamation[7] = {4, 4, 4, 4, 4, 0, 4};
    static const uint8_t period[7] = {0, 0, 0, 0, 0, 6, 6};
    static const uint8_t comma[7] = {0, 0, 0, 0, 0, 6, 4};
    static const uint8_t colon[7] = {0, 6, 6, 0, 6, 6, 0};
    static const uint8_t dash[7] = {0, 0, 0, 31, 0, 0, 0};
    static const uint8_t slash[7] = {1, 2, 4, 8, 16, 0, 0};
    static const uint8_t plus[7] = {0, 4, 4, 31, 4, 4, 0};
    static const uint8_t equals[7] = {0, 31, 0, 31, 0, 0, 0};

    if (character >= '0' && character <= '9') {
        return digits[character - '0'];
    }
    if (character >= 'a' && character <= 'z') {
        character -= 'a' - 'A';
    }
    if (character >= 'A' && character <= 'Z') {
        return letters[character - 'A'];
    }
    switch (character) {
    case ' ': return blank;
    case '!': return exclamation;
    case '.': return period;
    case ',': return comma;
    case ':': return colon;
    case '-': return dash;
    case '/': return slash;
    case '+': return plus;
    case '=': return equals;
    default: return unknown;
    }
}

static void console_scroll(char cells[CONSOLE_ROWS][CONSOLE_COLUMNS], int *row, int *column)
{
    char top[CONSOLE_COLUMNS + 1];

    memmove(cells[0], cells[1], (CONSOLE_ROWS - 1) * CONSOLE_COLUMNS);
    memset(cells[CONSOLE_ROWS - 1], ' ', CONSOLE_COLUMNS);
    memcpy(console_top_row_snapshot, cells[0], CONSOLE_COLUMNS);
    memcpy(top, cells[0], CONSOLE_COLUMNS);
    top[CONSOLE_COLUMNS] = '\0';
    ++console_scroll_count;
    ESP_LOGI(TAG, "scroll #%u, new top [%s]", (unsigned)console_scroll_count, top);
    *row = CONSOLE_ROWS - 1;
    *column = 0;
}

/* Lazy scrolling: a newline (or wrap) at the bottom row only marks that the
 * next printable character needs a fresh row; the actual scroll is deferred
 * until then. Writing exactly CONSOLE_ROWS lines therefore leaves the screen
 * completely full instead of showing a blank bottom row. */
static bool console_scroll_pending;

static void console_put_character(char cells[CONSOLE_ROWS][CONSOLE_COLUMNS],
                                  int *row, int *column, uint8_t character)
{
    if (character == '\r') {
        *column = 0;
        return;
    }
    if (character == '\n') {
        *column = 0;
        ++console_newline_count;
        if (*row < CONSOLE_ROWS - 1) {
            ++*row;
        } else {
            console_scroll_pending = true;
        }
        return;
    }
    if (character < ' ' || character > '~') {
        return;
    }
    if (console_scroll_pending) {
        console_scroll(cells, row, column);
        console_scroll_pending = false;
    }
    cells[*row][(*column)++] = (char)character;
    if (*column == CONSOLE_COLUMNS) {
        *column = 0;
        if (*row < CONSOLE_ROWS - 1) {
            ++*row;
        } else {
            console_scroll_pending = true;
        }
    }
}

static esp_err_t console_refresh(const char cells[CONSOLE_ROWS][CONSOLE_COLUMNS])
{
    uint16_t *frame = console_frame[console_frame_index];

    for (int row = 0; row < CONSOLE_ROWS; ++row) {
        for (int y = 0; y < CONSOLE_FONT_HEIGHT * CONSOLE_SCALE; ++y) {
            uint16_t *pixels = &frame[(row * CONSOLE_FONT_HEIGHT * CONSOLE_SCALE + y) * LCD_WIDTH];
            for (int column = 0; column < CONSOLE_COLUMNS; ++column) {
                const uint8_t *glyph = glyph_rows(cells[row][column]);
                uint8_t bits = y / CONSOLE_SCALE < 7 ? glyph[y / CONSOLE_SCALE] : 0;
                for (int x = 0; x < CONSOLE_FONT_WIDTH * CONSOLE_SCALE; ++x) {
                    int glyph_column = x / CONSOLE_SCALE;
                    pixels[column * CONSOLE_FONT_WIDTH * CONSOLE_SCALE + x] =
                        glyph_column < 5 && (bits & (1U << (4 - glyph_column))) ? UINT16_MAX : 0;
                }
            }
        }
    }
    console_frame_index ^= 1;
    esp_err_t error = esp_lcd_panel_draw_bitmap(panel, 0, 0, LCD_WIDTH, LCD_HEIGHT, frame);
    if (error != ESP_OK) {
        return error;
    }
    /* Wait for the frame transfer to complete: the driver queues the color
     * data asynchronously, so the buffers must not be rebuilt while the DMA
     * is still reading them. */
    if (xSemaphoreTake(console_frame_done, pdMS_TO_TICKS(200)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    return ESP_OK;
}

static void lcd_console_task(void *argument)
{
    char cells[CONSOLE_ROWS][CONSOLE_COLUMNS];
    uint8_t character;
    int row = 0;
    int column = 0;
    i2c_master_bus_handle_t i2c_bus;
    esp_err_t error = initialize_power(&i2c_bus);
    if (error == ESP_OK) {
        error = initialize_panel();
    }
    if (error == ESP_OK) {
        console_frame_done = xSemaphoreCreateBinary();
        if (console_frame_done == NULL) {
            error = ESP_ERR_NO_MEM;
        }
    }
    for (int i = 0; error == ESP_OK && i < 2; ++i) {
        /* 64-byte alignment and MALLOC_CAP_SPIRAM: EDMA reads the frame
         * buffer directly from octal PSRAM (psram_dma_direct). */
        console_frame[i] = heap_caps_aligned_alloc(64,
                                                   (size_t)LCD_WIDTH * LCD_HEIGHT * sizeof(uint16_t),
                                                   MALLOC_CAP_SPIRAM);
        if (console_frame[i] == NULL) {
            ESP_LOGE(TAG, "allocate frame buffer %d failed", i);
            error = ESP_ERR_NO_MEM;
        }
    }
    if (error != ESP_OK) {
        ESP_LOGE(TAG, "initialize LCD console: %s", esp_err_to_name(error));
        vTaskDelete(NULL);
        return;
    }

    memset(cells, ' ', sizeof(cells));
    memcpy(console_top_row_snapshot, cells[0], CONSOLE_COLUMNS);
    if (console_refresh(cells) != ESP_OK) {
        ESP_LOGE(TAG, "clear LCD console failed");
        vTaskDelete(NULL);
        return;
    }
    ESP_LOGI(TAG, "console ready: %d columns x %d rows", CONSOLE_COLUMNS, CONSOLE_ROWS);

    for (;;) {
        if (xQueueReceive(console_queue, &character, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        console_put_character(cells, &row, &column, character);
        for (int count = 1; count < CONSOLE_RENDER_BATCH &&
                            xQueueReceive(console_queue, &character, 0) == pdTRUE; ++count) {
            console_put_character(cells, &row, &column, character);
        }
        error = console_refresh(cells);
        if (error != ESP_OK) {
            ESP_LOGE(TAG, "refresh LCD console: %s", esp_err_to_name(error));
        }
    }
}

static int lcd_console_open(void *context, const char *path, int flags, int mode)
{
    (void)context;
    (void)path;
    (void)mode;
    if ((flags & O_ACCMODE) == O_RDONLY) {
        errno = EACCES;
        return -1;
    }
    return 0;
}

static int lcd_console_close(void *context, int fd)
{
    (void)context;
    (void)fd;
    return 0;
}

static size_t console_enqueue(const uint8_t *data, size_t size)
{
    size_t accepted = 0;

    for (; accepted < size; ++accepted) {
        if (xQueueSend(console_queue, &data[accepted], CONSOLE_WRITE_WAIT_TICKS) != pdTRUE) {
            portENTER_CRITICAL(&console_drop_lock);
            console_dropped_bytes += (uint32_t)(size - accepted);
            portEXIT_CRITICAL(&console_drop_lock);
            break;
        }
    }
    return accepted;
}

static ssize_t lcd_console_write(void *context, int fd, const void *data, size_t size)
{
    (void)context;
    (void)fd;
    size_t accepted = console_enqueue(data, size);
    if (accepted != size) {
        errno = EAGAIN;
    }
    return (ssize_t)accepted;
}

static const esp_vfs_t lcd_console_vfs = {
    /* ESP_VFS_FLAG_STATIC is rejected by esp_vfs_register in IDF v6.x. */
    .flags = ESP_VFS_FLAG_CONTEXT_PTR,
    .write_p = lcd_console_write,
    .open_p = lcd_console_open,
    .close_p = lcd_console_close,
};

int waveshare_lcd_console_init(void)
{
    if (console_task != NULL) {
        return ESP_OK;
    }
    console_queue = xQueueCreateStatic(CONSOLE_QUEUE_LENGTH, sizeof(uint8_t),
                                       console_queue_storage, &console_queue_buffer);
    if (console_queue == NULL) {
        return ESP_ERR_NO_MEM;
    }
    esp_err_t error = esp_vfs_register("/dev/lcdcon", &lcd_console_vfs, NULL);
    if (error != ESP_OK) {
        return error;
    }
    console_task = xTaskCreateStatic(lcd_console_task, "lcd_console",
                                     sizeof(console_task_stack) / sizeof(console_task_stack[0]),
                                     NULL, 5, console_task_stack, &console_task_buffer);
    if (console_task == NULL) {
        esp_vfs_unregister("/dev/lcdcon");
        console_queue = NULL;
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

/* Write one line to the LCD console: the string plus a newline. Intended as
 * the primary application API (e.g. called from Free Pascal as
 * `procedure lcd_writeln(line: PChar); cdecl; external;`). Bytes beyond the
 * console queue capacity are dropped and counted by
 * waveshare_lcd_console_dropped_bytes(). */
void lcd_writeln(const char *line)
{
    static const uint8_t newline = '\n';

    if (console_queue == NULL) {
        return;
    }
    if (line != NULL && *line != '\0') {
        console_enqueue((const uint8_t *)line, strlen(line));
    }
    console_enqueue(&newline, 1);
}

void lcd_write(const char *line)
{
    if (console_queue == NULL) {
        return;
    }
    if (line != NULL && *line != '\0') {
        console_enqueue((const uint8_t *)line, strlen(line));
    }
}

uint32_t waveshare_lcd_console_dropped_bytes(void)
{
    uint32_t dropped;
    portENTER_CRITICAL(&console_drop_lock);
    dropped = console_dropped_bytes;
    portEXIT_CRITICAL(&console_drop_lock);
    return dropped;
}

/* Diagnostic snapshot for bring-up: newline/scroll counters and the current
 * top console row (blank-padded, not NUL-terminated; buffer length must be
 * CONSOLE_COLUMNS + 1). */
void waveshare_lcd_console_line_stats(uint32_t *newlines, uint32_t *scrolls,
                                      char *top_row, size_t top_row_size)
{
    if (newlines != NULL) {
        *newlines = console_newline_count;
    }
    if (scrolls != NULL) {
        *scrolls = console_scroll_count;
    }
    if (top_row != NULL && top_row_size >= CONSOLE_COLUMNS + 1) {
        memcpy(top_row, console_top_row_snapshot, CONSOLE_COLUMNS);
        top_row[CONSOLE_COLUMNS] = '\0';
    }
}
