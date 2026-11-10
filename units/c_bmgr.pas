{ c_bmgr - Pascal binding (L1, C-ABI shadow) for the esp_board_manager C
  component. Layer grammar (units/README.md): `c_<C component short name>`
  = L1 binding - hand-converted C headers only, `cdecl; external` functions
  keep their C names; Pascal-native services live in unprefixed L2 units.

  Source: managed_components/espressif__esp_board_manager (lvgl-s31 SDK tree)
    include/esp_board_manager.h        core API
    include/esp_board_manager_defs.h   reserved device-name / type strings
    devices/dev_display_lcd/dev_display_lcd.h
    devices/dev_lcd_touch/dev_lcd_touch.h

  Converted from the C headers flattened with the SDK project's own
  toolchain and sdkconfig (riscv32-esp-elf-gcc -E against that project's
  build/config/sdkconfig.h). The board is ESP-Mosaico, so of the
  dev_display_lcd sub-type set only SPI survives the CONFIG gating
  (CONFIG_ESP_BOARD_DEV_DISPLAY_LCD_SUB_DSI/RGB/RGB_3WIRE_SPI/I80/PARLIO
  are all off there) - which is why sub_cfg's union below has a single
  SPI variant; the DSI/RGB register paths main.c keeps behind #if are
  not part of this configuration's ABI and are omitted.

  Layout facts (riscv32 ILP32, verified against the C build):
    pointer 4 B, long 4 B, size_t = unsigned int 4 B, C enum 4 B
    (-$MINENUMSIZE 4), C bool 1 B. 1-bit C bitfields resolve to whole
    storage words; the mask constants below encode gcc's little-endian
    (LSB-first) bitfield packing. -$PACKRECORDS C makes FPC compute the
    same padding gcc does (verified sizes: dev_display_lcd_config_t = 108,
    spi_sub 72, touch_config_t 108, i2c_sub 56, spi_sub 48).

  All API symbols are `external` and resolve against the whole-archived
  libespressif__esp_board_manager.a (build.sh --lib). }

unit c_bmgr;

{$mode objfpc}{$H+}
{$packrecords C}
{$minenumsize 4}

interface

{ ------------------------------------------------------------------ types }

{ <stdint.h> scalar surface the headers use }
type
  cint8   = shortint;
  cuint8  = byte;
  cint16  = smallint;
  cuint16 = word;
  cint32  = longint;
  cuint32 = longword;
  cint64  = int64;
  cuint64 = qword;
  { the generic C int/unsigned int - 4 B on riscv32 }
  cint    = longint;
  cuint   = longword;
  size_t  = cuint;      { = unsigned int on riscv32 }
  { C `bool` in records is 1 B - FPC's plain boolean matches }
  cbool   = boolean;
  ppvoid  = ^pointer;

  { esp_err_t is `int` (esp_err.h): ESP_OK = 0, ESP_FAIL = -1 }
  esp_err_t = cint;

const
  ESP_OK                = 0;
  ESP_FAIL              = cint(-1);
  ESP_ERR_NO_MEM        = $101;
  ESP_ERR_INVALID_ARG   = $102;
  ESP_ERR_INVALID_STATE = $103;
  ESP_ERR_NOT_FOUND     = $105;
  ESP_ERR_TIMEOUT       = $107;

{ ---------------------------------------------------- esp_board_manager.h }

type
  { struct esp_board_info - board identity exposed by the manager (20 B) }
  Pesp_board_info_t = ^esp_board_info_t;
  esp_board_info_t = record
    name:         PChar;
    chip:         PChar;
    version:      PChar;
    description:  PChar;
    manufacturer: PChar;
  end;

{ ------------------------------------------------- esp_board_manager_defs.h

  Reserved device names (init_device_by_name keys) and device type keys,
  verbatim. As C they are #define string literals; as Pascal they are
  compile-time string constants, used the same way. }
const
  ESP_BOARD_DEVICE_NAME_AUDIO_DAC        = 'audio_dac';
  ESP_BOARD_DEVICE_NAME_AUDIO_ADC        = 'audio_adc';
  ESP_BOARD_DEVICE_NAME_FS_SDCARD        = 'fs_sdcard';
  ESP_BOARD_DEVICE_NAME_FS_FAT           = 'fs_fat';
  ESP_BOARD_DEVICE_NAME_LCD_TOUCH        = 'lcd_touch';
  ESP_BOARD_DEVICE_NAME_DISPLAY_LCD      = 'display_lcd';
  ESP_BOARD_DEVICE_NAME_LCD_POWER        = 'lcd_power';
  ESP_BOARD_DEVICE_NAME_LCD_BRIGHTNESS   = 'lcd_brightness';
  ESP_BOARD_DEVICE_NAME_LED_STRIP        = 'led_strip';
  ESP_BOARD_DEVICE_NAME_FS_SPIFFS        = 'fs_spiffs';
  ESP_BOARD_DEVICE_NAME_LITTLEFS         = 'littlefs';
  ESP_BOARD_DEVICE_NAME_GPIO_EXPANDER    = 'gpio_expander';
  ESP_BOARD_DEVICE_NAME_CAMERA           = 'camera';
  ESP_BOARD_DEVICE_NAME_KNOB             = 'knob';
  ESP_BOARD_DEVICE_NAME_ETHERNET         = 'ethernet';
  ESP_BOARD_DEVICE_NAME_SD_POWER         = 'sdcard_power_ctrl';
  ESP_BOARD_DEVICE_NAME_ADC_BUTTON_0     = 'adc_button_0';
  ESP_BOARD_DEVICE_NAME_ADC_BUTTON_1     = 'adc_button_1';
  ESP_BOARD_DEVICE_NAME_ADC_BUTTON_2     = 'adc_button_2';
  ESP_BOARD_DEVICE_NAME_ADC_BUTTON_3     = 'adc_button_3';
  ESP_BOARD_DEVICE_NAME_ADC_BUTTON_4     = 'adc_button_4';
  ESP_BOARD_DEVICE_NAME_ADC_BUTTON_5     = 'adc_button_5';
  ESP_BOARD_DEVICE_NAME_ADC_BUTTON_GROUP = 'adc_button_group';

  ESP_BOARD_DEVICE_TYPE_AUDIO_CODEC   = 'audio_codec';
  ESP_BOARD_DEVICE_TYPE_FS_FAT        = 'fs_fat';
  ESP_BOARD_DEVICE_TYPE_FS_SPIFFS     = 'fs_spiffs';
  ESP_BOARD_DEVICE_TYPE_LITTLEFS      = 'littlefs';
  ESP_BOARD_DEVICE_TYPE_LCD_TOUCH     = 'lcd_touch';
  ESP_BOARD_DEVICE_TYPE_DISPLAY_LCD   = 'display_lcd';
  ESP_BOARD_DEVICE_TYPE_GPIO_CTRL     = 'gpio_ctrl';
  ESP_BOARD_DEVICE_TYPE_LEDC_CTRL     = 'ledc_ctrl';
  ESP_BOARD_DEVICE_TYPE_LED_STRIP     = 'led_strip';
  ESP_BOARD_DEVICE_TYPE_GPIO_EXPANDER = 'gpio_expander';
  ESP_BOARD_DEVICE_TYPE_CAMERA        = 'camera';
  ESP_BOARD_DEVICE_TYPE_POWER_CTRL    = 'power_ctrl';
  ESP_BOARD_DEVICE_TYPE_BUTTON        = 'button';
  ESP_BOARD_DEVICE_TYPE_KNOB          = 'knob';
  ESP_BOARD_DEVICE_TYPE_ETHERNET      = 'ethernet';

  { dev_display_lcd.h sub-type strings - the "sub_type" key of a
    display_lcd board_devices.yaml entry; main.c strcmp()s them }
  ESP_BOARD_DEVICE_LCD_SUB_TYPE_DSI           = 'dsi';
  ESP_BOARD_DEVICE_LCD_SUB_TYPE_SPI           = 'spi';
  ESP_BOARD_DEVICE_LCD_SUB_TYPE_PARLIO        = 'parlio';
  ESP_BOARD_DEVICE_LCD_SUB_TYPE_RGB           = 'rgb';
  ESP_BOARD_DEVICE_LCD_SUB_TYPE_RGB_3WIRE_SPI = 'rgb_3wire_spi';
  ESP_BOARD_DEVICE_LCD_SUB_TYPE_I80           = 'i80';

{ ------------------------------------- esp_lcd types the device headers use }

type
  { enum lcd_rgb_element_order_t (esp_hal_lcd hal/color_types.h) }
  lcd_rgb_element_order_t = (
    COLOR_RGB_ELEMENT_ORDER_RGB = 0,
    COLOR_RGB_ELEMENT_ORDER_BGR = 1
  );

  { enum lcd_rgb_data_endian_t (esp_hal_lcd hal/lcd_types.h) }
  lcd_rgb_data_endian_t = (
    LCD_RGB_DATA_ENDIAN_BIG = 0,     { MSB first }
    LCD_RGB_DATA_ENDIAN_LITTLE = 1   { LSB first }
  );

  { enum gpio_num_t - only -1 (= GPIO_NUM_NC, "not connected") and driver-
    chosen GPIOs appear in config records, so a cint alias mirrors the C
    enum exactly in size and rank }
  gpio_num_t = cint;

const
  GPIO_NUM_NC = cint(-1);

{ opaque LCD handles }
type
  esp_lcd_panel_io_handle_t = pointer;   { esp_lcd_panel_io_t* }
  Pesp_lcd_panel_io_handle_t = ^esp_lcd_panel_io_handle_t;
  esp_lcd_panel_handle_t = pointer;      { esp_lcd_panel_t* }
  Pesp_lcd_panel_handle_t = ^esp_lcd_panel_handle_t;
  esp_lcd_spi_bus_handle_t = cint;

  { bool (*esp_lcd_panel_io_color_trans_done_cb_t)(io, edata, user_ctx) }
  TColorTransDoneCb = function(io: esp_lcd_panel_io_handle_t;
    edata: pointer; user_ctx: pointer): cbool; cdecl;

{ ------------------------------------------ esp_lcd_panel_io_spi.h (IDF 6.1) }

type
  { struct esp_lcd_panel_io_spi_config_t - 44 B; C offsets: cs 0, dc 4,
    spi_mode 8, pclk_hz 12, trans_queue_depth 16, on_color_trans_done 20,
    user_ctx 24, lcd_cmd_bits 28, lcd_param_bits 32, cs_ena_pretrans 36,
    cs_ena_posttrans 37, flags 40 }
  Pesp_lcd_panel_io_spi_config_t = ^esp_lcd_panel_io_spi_config_t;
  esp_lcd_panel_io_spi_config_t = record
    cs_gpio_num:         gpio_num_t;    { 0 }
    dc_gpio_num:         gpio_num_t;    { 4 }
    spi_mode:            cint;          { 8  (0..3) }
    pclk_hz:             cuint;         { 12 }
    trans_queue_depth:   size_t;        { 16 }
    on_color_trans_done: TColorTransDoneCb;  { 20 }
    user_ctx:            pointer;       { 24 }
    lcd_cmd_bits:        cint;          { 28 }
    lcd_param_bits:      cint;          { 32 }
    cs_ena_pretrans:     cuint8;        { 36 }
    cs_ena_posttrans:    cuint8;        { 37 }
    { struct esp_lcd_spi_flags_t: 9x1-bit `unsigned` bitfields in one
      word, aligned 4, gcc little-endian: bit0 dc_high_on_cmd ... }
    flags: cuint;                       { 40 }
  end;  { 44 }

const
  { esp_lcd_spi_flags_t masks, LSB-first }
  SPI_FLAG_dc_high_on_cmd   = $0001;
  SPI_FLAG_dc_low_on_data   = $0002;
  SPI_FLAG_dc_low_on_param  = $0004;
  SPI_FLAG_octal_mode       = $0008;
  SPI_FLAG_quad_mode        = $0010;
  SPI_FLAG_sio_mode         = $0020;
  SPI_FLAG_psram_dma_direct = $0040;
  SPI_FLAG_lsb_first        = $0080;
  SPI_FLAG_cs_high_active   = $0100;

{ ------------------------------------------ esp_lcd_panel_dev.h (IDF 6.1) }

type
  { struct esp_lcd_panel_dev_config_t - 24 B }
  Pesp_lcd_panel_dev_config_t = ^esp_lcd_panel_dev_config_t;
  esp_lcd_panel_dev_config_t = record
    rgb_ele_order:  lcd_rgb_element_order_t;  { 0 }
    data_endian:    lcd_rgb_data_endian_t;    { 4 }
    bits_per_pixel: cuint;                    { 8 }
    reset_gpio_num: gpio_num_t;               { 12 (-1 = not used) }
    vendor_config:  pointer;                  { 16 }
    { struct flags: reset_active_high:1 }
    flags: cuint;                             { 20 }
  end;  { 24 }

const
  PANEL_DEV_FLAG_reset_active_high = $0001;

{ ------------------------------------------ esp_lcd_panel_io.h (I2C twin) }

type
  { struct esp_lcd_panel_io_i2c_config_t - 40 B }
  Pesp_lcd_panel_io_i2c_config_t = ^esp_lcd_panel_io_i2c_config_t;
  esp_lcd_panel_io_i2c_config_t = record
    dev_addr:            cuint;   { 0 }
    scl_speed_hz:        cuint;   { 4 }
    control_phase_bytes: size_t;  { 8 }
    dc_bit_offset:       cuint8;  { 12 }
    lcd_cmd_bits:        cint;    { 16 }
    lcd_param_bits:      cint;    { 20 }
    on_color_trans_done: TColorTransDoneCb;  { 24 }
    user_ctx:            pointer; { 28 }
    { struct flags: dc_low_on_data:1 | disable_control_phase:1 }
    flags: cuint;                 { 32 }
    transaction_timeout_ms: cint; { 36 }
  end;  { 40 }

const
  I2C_FLAG_dc_low_on_data        = $0001;
  I2C_FLAG_disable_control_phase = $0002;

{ a couple of esp_lcd panel-IO entry points the device factories use }
function esp_lcd_new_panel_io_spi(bus: esp_lcd_spi_bus_handle_t;
  io_config: Pesp_lcd_panel_io_spi_config_t;
  ret_io: Pesp_lcd_panel_io_handle_t): esp_err_t; cdecl; external;
function esp_lcd_panel_io_tx_color(io: esp_lcd_panel_io_handle_t;
  lcd_cmd: cint; color: pointer; color_size: size_t): esp_err_t; cdecl; external;
function esp_lcd_panel_io_del(io: esp_lcd_panel_io_handle_t): esp_err_t; cdecl; external;

{ -------------------------------------------------------- dev_display_lcd }

type
  { enum dev_display_lcd_frame_format_t }
  dev_display_lcd_frame_format_t = (
    DEV_DISPLAY_LCD_FRAME_FORMAT_UNKNOWN   = 0,
    DEV_DISPLAY_LCD_FRAME_FORMAT_RGB565_LE = 1,
    DEV_DISPLAY_LCD_FRAME_FORMAT_RGB565_BE = 2,
    DEV_DISPLAY_LCD_FRAME_FORMAT_BGR888    = 3,
    DEV_DISPLAY_LCD_FRAME_FORMAT_RGB888    = 4
  );

  { struct dev_display_lcd_spi_sub_config_t - 72 B:
    spi_name 0, panel_config 4 (24 B), io_spi_config 28 (44 B) }
  Pdev_display_lcd_spi_sub_config_t = ^dev_display_lcd_spi_sub_config_t;
  dev_display_lcd_spi_sub_config_t = record
    spi_name:      PChar;                          { 0 }
    panel_config:  esp_lcd_panel_dev_config_t;     { 4 }
    io_spi_config: esp_lcd_panel_io_spi_config_t;  { 28 }
  end;  { 72 }

  { struct dev_display_lcd_handles_t - what get_device_handle(
    "display_lcd") hands back; io first, panel second (8 B) }
  Pdev_display_lcd_handles_t = ^dev_display_lcd_handles_t;
  dev_display_lcd_handles_t = record
    io_handle:    esp_lcd_panel_io_handle_t;  { 0 }
    panel_handle: esp_lcd_panel_handle_t;     { 4 }
  end;

  { struct dev_display_lcd_config - 108 B (sub_cfg union is 72 B because
    only the SPI member survives the CONFIG gating).
    The five one-bit uint8 bitfields at offset 16 (swap_xy, mirror_x,
    mirror_y, need_reset, invert_color) are encoded LSB-first in
    config_flags; the mask constants below decode them like gcc does. }
  Pdev_display_lcd_config_t = ^dev_display_lcd_config_t;
  dev_display_lcd_config_t = record
    name:           PChar;     { 0 }
    chip:           PChar;     { 4 }
    sub_type:       PChar;     { 8 }
    lcd_width:      cuint16;   { 12 }
    lcd_height:     cuint16;   { 14 }
    config_flags:   cuint8;    { 16, was 5x1-bit uint8 bitfields }
    rgb_ele_order:  lcd_rgb_element_order_t;   { 20 }
    data_endian:    lcd_rgb_data_endian_t;     { 24 }
    bits_per_pixel: cuint;     { 28 }
    { union sub_cfg - single active member after the sdkconfig gating }
    sub_cfg: record
      case Byte of
        0: (spi: dev_display_lcd_spi_sub_config_t);
    end;                       { 32 }
    frame_format: dev_display_lcd_frame_format_t;   { 104 }
  end;  { 108 }

const
  { config_flags bit masks, LSB-first }
  LCD_BIT_swap_xy      = $01;
  LCD_BIT_mirror_x     = $02;
  LCD_BIT_mirror_y     = $04;
  LCD_BIT_need_reset   = $08;
  LCD_BIT_invert_color = $10;

{ ---------------------------------------------------------- dev_lcd_touch }

type
  esp_lcd_touch_handle_t = pointer;  { esp_lcd_touch_t* - opaque }
  Pesp_lcd_touch_handle_t = ^esp_lcd_touch_handle_t;

  { void (*esp_lcd_touch_interrupt_callback_t)(tp, user_ctx?) - the C
    prototype is void(*)(esp_lcd_touch_handle_t) with no user data }
  TTouchIntrCb = procedure(tp: esp_lcd_touch_handle_t); cdecl;

  { struct esp_lcd_touch_config_t - 36 B }
  Pesp_lcd_touch_config_t = ^esp_lcd_touch_config_t;
  esp_lcd_touch_config_t = record
    x_max:        cuint16;   { 0 }
    y_max:        cuint16;   { 2 }
    rst_gpio_num: gpio_num_t;  { 4 (-1 = not used) }
    int_gpio_num: gpio_num_t;  { 8 (-1 = not used) }
    { struct levels: reset:1 | interrupt:1 }
    levels: cuint;             { 12 }
    { struct flags: swap_xy:1 | mirror_x:1 | mirror_y:1 }
    flags: cuint;              { 16 }
    { void (*process_coordinates)(tp, x, y, strength, point_num, max) }
    process_coordinates: pointer;  { 20 }
    interrupt_callback: TTouchIntrCb;  { 24 }
    user_data:   pointer;      { 28 }
    driver_data: pointer;      { 32 }
  end;  { 36 }

const
  TOUCH_LEVEL_reset     = $0001;
  TOUCH_LEVEL_interrupt = $0002;
  TOUCH_FLAG_swap_xy  = $0001;
  TOUCH_FLAG_mirror_x = $0002;
  TOUCH_FLAG_mirror_y = $0004;

type
  { struct dev_lcd_touch_i2c_sub_config_t - 56 B }
  Pdev_lcd_touch_i2c_sub_config_t = ^dev_lcd_touch_i2c_sub_config_t;
  dev_lcd_touch_i2c_sub_config_t = record
    i2c_name:       PChar;    { 0 }
    i2c_addr_count: size_t;   { 4 }
    i2c_addr: array[0..3] of cuint16;  { 8 }
    io_i2c_config: esp_lcd_panel_io_i2c_config_t;  { 16 }
  end;  { 56 }

  { struct dev_lcd_touch_spi_sub_config_t - 48 B }
  Pdev_lcd_touch_spi_sub_config_t = ^dev_lcd_touch_spi_sub_config_t;
  dev_lcd_touch_spi_sub_config_t = record
    spi_name: PChar;    { 0 }
    io_spi_config: esp_lcd_panel_io_spi_config_t;  { 4 }
  end;  { 48 }

  { struct dev_lcd_touch_handles_t - get_device_handle("lcd_touch") gives
    this back: touch first, io second (8 B) }
  Pdev_lcd_touch_handles_t = ^dev_lcd_touch_handles_t;
  dev_lcd_touch_handles_t = record
    touch_handle: esp_lcd_touch_handle_t;      { 0 }
    io_handle:    esp_lcd_panel_io_handle_t;   { 4 }
  end;

  { struct dev_lcd_touch_config_t - 108 B: name/chip/type/sub_type, then
    touch_config (36 B @16), then sub_cfg union @52 (56 B, I2C variant
    larger). The C field named "type" is renamed "typ" ("type" is a
    Pascal keyword). }
  Pdev_lcd_touch_config_t = ^dev_lcd_touch_config_t;
  dev_lcd_touch_config_t = record
    name:     PChar;   { 0 }
    chip:     PChar;   { 4 }
    typ:      PChar;   { 8, C name: type }
    sub_type: PChar;   { 12 }
    touch_config: esp_lcd_touch_config_t;  { 16 }
    sub_cfg: record
      case Byte of
        0: (i2c: dev_lcd_touch_i2c_sub_config_t);
        1: (spi: dev_lcd_touch_spi_sub_config_t);
    end;               { 52 }
  end;  { 108 }

{ ------------------------------------------------- manager API (esp_board_manager.h) }

{ Resolved from the whole-archived libespressif__esp_board_manager.a }
function esp_board_manager_init: esp_err_t; cdecl; external;
function esp_board_manager_init_device_by_name(dev_name: PChar): esp_err_t; cdecl; external;
function esp_board_manager_deinit_device_by_name(dev_name: PChar): esp_err_t; cdecl; external;
function esp_board_manager_get_device_handle(dev_name: PChar;
  device_handle: ppvoid): esp_err_t; cdecl; external;
function esp_board_manager_get_periph_handle(periph_name: PChar;
  periph_handle: ppvoid): esp_err_t; cdecl; external;
function esp_board_manager_get_device_config(dev_name: PChar;
  config: ppvoid): esp_err_t; cdecl; external;
function esp_board_manager_get_board_info(board_info: Pesp_board_info_t): esp_err_t; cdecl; external;
{ esp_board_device.h - write the APP-layer config copy for a device
  (rejected while the device is initialized; the next init_device_by_name
  builds from the effective config). config_size = the full generated
  config record size, e.g. 108 for dev_display_lcd_config_t }
function esp_board_device_override_config(name: PChar; config: pointer;
  config_size: cuint16): esp_err_t; cdecl; external;

{ Applications normally never call these directly - init_device_by_name
  dispatches through the manager registry to the factory for the active
  board_devices.yaml entry }
function dev_display_lcd_init(cfg: pointer; cfg_size: cint; device_handle: ppvoid): cint; cdecl; external;
function dev_display_lcd_deinit(device_handle: pointer): cint; cdecl; external;
function dev_lcd_touch_init(cfg: pointer; cfg_size: cint; device_handle: ppvoid): cint; cdecl; external;
function dev_lcd_touch_deinit(device_handle: pointer): cint; cdecl; external;

implementation

end.
