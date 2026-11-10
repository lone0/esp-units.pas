{ c_esp_lcd - Pascal binding (L1, C-ABI shadow) for the esp_lcd C component
  panel operations (IDF 6.1 components/esp_lcd, src/esp_lcd_panel_ops.c).

  Layer grammar (units/README.md): `c_<C component short name>` = L1
  binding - hand-converted C headers only, `cdecl; external` functions
  keep their C names; Pascal-native services live in unprefixed L2 units.

  Scope, added per business need ("used in one place, added in one place"):
  the panel-level operations for applications that drive the panel
  directly, bypassing LVGL. The opaque handle types
  (esp_lcd_panel_handle_t & co) live in c_bmgr - they are the esp_lcd
  types the BMGR device headers pass around, and c_bmgr is the shadow of
  the component that hands those handles out.

  Frame-flush semantics a direct caller must know (read out of IDF 6.1
  spi/esp_lcd_panel_io_spi.c, 2026-11-08):
    - esp_lcd_panel_draw_bitmap over an SPI panel IO ends in
      panel_io_spi_tx_color, which QUEUES the color DMA chunks
      (spi_device_queue_trans, pool = trans_queue_depth) and returns
      before the wire has seen the data.
    - every draw_bitmap starts with CASET/RASET tx_param calls, and
      panel_io_spi_tx_param first WAITS for all in-flight transactions.
    => alternating draw_bitmap(A) / render into B / draw_bitmap(B) is a
    safe pipeline without any callback: the next flush's CASET polls the
    previous frame's DMA out, so the render of frame N+1 hides inside the
    DMA of frame N. Driving a SINGLE buffer this way tears/corrupts it -
    the render would run while its own DMA streams the same memory.

  All API symbols are `external` and resolve against libesp_lcd.a
  (build.sh --lib esp_lcd). }

unit c_esp_lcd;

{$mode objfpc}{$H+}
{$packrecords C}
{$minenumsize 4}

interface

uses
  c_bmgr;   { esp_lcd opaque handles (esp_lcd_panel_handle_t), esp_err_t }

{ esp_lcd_panel_ops.h (IDF 6.1): push one rectangle of color data into the
  panel's GRAM. The coordinates are inclusive window bounds in panel-native
  orientation. The color buffer must stay untouched until the NEXT
  draw_bitmap call starts sending its window commands (see the header
  comment: tx_color queues asynchronously, the next tx_param waits). }
function esp_lcd_panel_draw_bitmap(panel: esp_lcd_panel_handle_t;
  x0, y0, x1, y1: cint; color_data: pointer): esp_err_t; cdecl; external;

{ Run the panel's reset + vendor init sequence (init_cmds from the
  vendor_config the panel was created with) and turn the display on. Used
  after creating an application-owned panel object. }
function esp_lcd_panel_init(panel: esp_lcd_panel_handle_t): esp_err_t; cdecl; external;

implementation

end.
