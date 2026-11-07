{ c_lvgl - Pascal binding (L1, C-ABI shadow) for the LVGL 9.6 C library.
  Layer grammar (units/README.md): `c_<C component short name>` = L1
  binding - `cdecl; external` functions keep their C names; Pascal-native
  services live in unprefixed L2 units.

  Source: managed_components/lvgl__lvgl 9.6.0 in the lvgl-s31 SDK tree,
  include/lvgl/... This is a hand-converted WORKING SUBSET - the symbols
  the first Pascal UI needs (mirroring what lvgl_test_ui.c uses). It grows
  per business need; it is deliberately NOT the full lvgl.h.

  LVGL 9 facts baked in (all checked against the 9.6.0 headers):

    - lv_obj_t / lv_display_t / lv_event_t / lv_event_dsc_t / lv_font_t
      are opaque (lv_types.h:105-158) - plain pointer handles here. With
      typed pointers off (the FPC default) they interoperate freely with
      the other bindings' handle aliases (c_lvgl_adapter's plv_display_t
      etc.).

    - geometry coordinates are int32_t in v9 (lv_obj_pos.h:54/89/179),
      not v8's int16.

    - the active-screen symbol is lv_screen_active() (lv_display.h:528);
      the v8 name lv_scr_act survives only as a macro, so the real symbol
      is bound.

    - lv_obj_is_valid survives only as a macro alias of
      lv_obj_is_in_widget_tree (lv_api_map_v9_5.h:45) - the real symbol
      (lv_obj.h:866) is bound.

    - lv_color_t is a 3x uint8 struct (blue, green, red - lv_color.h:109)
      passed BY VALUE. The riscv32 psABI passes such small aggregates
      bitified into one register: blue in [7:0], green in [15:8], red in
      [23:16]. We never bind a C function *returning* lv_color_t; the
      style setters below take the packed cuint built by ColorMake. The
      pack order is the C struct's memory layout, little-endian. First-
      flash probe: a pure-color element must show exactly that color;
      if it does not, replace the packed-cuint params with a tiny C shim
      that repacks inside C.

    - lv_style_selector_t is uint32_t (lv_obj_style.h:88); 0 = the usual
      LV_PART_MAIN | LV_STATE_DEFAULT.

    - lv_font_montserrat_14 is the only font enabled in the lvgl-s31
      sdkconfig (also the default); bound as an external variable whose
      address is the handle, exactly like taking &lv_font_montserrat_14.

  All functions are `external` and resolve against liblvgl__lvgl.a
  (build.sh --lib lvgl__lvgl, a plain archive - no whole-archive). }

unit c_lvgl;

{$mode objfpc}{$H+}

interface

uses
  c_bmgr;  { cint/cuint/cint32/cbool scalar aliases }

{ -------------------------------------------------------- opaque handles }

type
  plv_obj_t       = pointer;  { lv_obj_t* (lv_types.h:105) }
  plv_display_t   = pointer;  { lv_display_t* (lv_types.h:119) }
  plv_event_t     = pointer;  { lv_event_t* (lv_types.h:127) }
  plv_event_dsc_t = pointer;  { lv_event_dsc_t* (lv_types.h:158) }
  plv_font_t      = pointer;  { const lv_font_t* (lv_types.h:138) }

  { void (*)(lv_event_t *e) - lv_event.h:29 }
  TlvEventCb = procedure(e: plv_event_t); cdecl;

{ ------------------------------------------------------------- constants }

const
  { lv_align_t (lv_area.h:51) - the in-screen values, verbatim order }
  LV_ALIGN_DEFAULT      = 0;
  LV_ALIGN_TOP_LEFT     = 1;
  LV_ALIGN_TOP_MID      = 2;
  LV_ALIGN_TOP_RIGHT    = 3;
  LV_ALIGN_BOTTOM_LEFT  = 4;
  LV_ALIGN_BOTTOM_MID   = 5;
  LV_ALIGN_BOTTOM_RIGHT = 6;
  LV_ALIGN_LEFT_MID     = 7;
  LV_ALIGN_RIGHT_MID    = 8;
  LV_ALIGN_CENTER       = 9;
  { LV_ALIGN_OUT_* continue from 10 (lv_area.h:63+) - add per need }

  { lv_event_code_t (lv_event.h:34) - the values in use, verbatim order;
    CLICKED = 10 in v9 (v8 had different numbering) }
  LV_EVENT_ALL      = 0;
  LV_EVENT_PRESSED  = 1;
  LV_EVENT_CLICKED  = 10;
  LV_EVENT_RELEASED = 11;

  { lv_style_selector_t: 0 = LV_PART_MAIN | LV_STATE_DEFAULT }
  LV_STYLE_MAIN = 0;

{ ------------------------------------------------------- packed lv_color_t }

{ lv_color_t memory layout is blue, green, red (lv_color.h:109); packed
  little-endian into one register per the psABI bitification rules. }
function ColorMake(r, g, b: Byte): cuint; inline;
function ColorBlack: cuint; inline;
function ColorWhite: cuint; inline;

{ -------------------------------------------------------------- objects }

function lv_screen_active: plv_obj_t; cdecl; external;                      { lv_display.h:528 }
function lv_obj_create(parent: plv_obj_t): plv_obj_t; cdecl; external;      { lv_obj.h:226 }
function lv_label_create(parent: plv_obj_t): plv_obj_t; cdecl; external;    { lv_label.h:80 }
function lv_button_create(parent: plv_obj_t): plv_obj_t; cdecl; external;   { lv_button.h:37 }
procedure lv_label_set_text(obj: plv_obj_t; text: PChar); cdecl; external;  { lv_label.h:94 }

{ -------------------------------------------------------------- geometry }

procedure lv_obj_set_pos(obj: plv_obj_t; x, y: cint32); cdecl; external;    { lv_obj_pos.h:54 }
procedure lv_obj_set_size(obj: plv_obj_t; w, h: cint32); cdecl; external;   { lv_obj_pos.h:89 }
procedure lv_obj_align(obj: plv_obj_t; align: cint; x_ofs, y_ofs: cint32); cdecl; external;  { lv_obj_pos.h:179 }
procedure lv_obj_center(obj: plv_obj_t); cdecl; external;                   { lv_obj_pos.h:199 }

{ ------------------------------------------------------------------ tree }

procedure lv_obj_delete(obj: plv_obj_t); cdecl; external;                   { lv_obj_tree.h:46 }
procedure lv_obj_clean(obj: plv_obj_t); cdecl; external;                    { lv_obj_tree.h:54 }
function lv_obj_is_in_widget_tree(obj: plv_obj_t): cbool; cdecl; external;  { lv_obj.h:866;
  v8 name lv_obj_is_valid is a macro alias in 9.6 }

{ ----------------------------------------------------------------- events }

function lv_obj_add_event_cb(obj: plv_obj_t; event_cb: TlvEventCb;
  filter: cint; user_data: pointer): plv_event_dsc_t; cdecl; external;      { lv_obj_event.h:84 }
function lv_event_get_code(e: plv_event_t): cint; cdecl; external;          { lv_event.h:207 }

{ ----------------------------------------------------------------- styles }

procedure lv_obj_set_style_bg_color(obj: plv_obj_t; value: cuint;
  selector: cuint); cdecl; external;                                        { lv_obj_style_gen.h:1720 }
procedure lv_obj_set_style_text_color(obj: plv_obj_t; value: cuint;
  selector: cuint); cdecl; external;                                        { lv_obj_style_gen.h:2324 }
procedure lv_obj_set_style_text_font(obj: plv_obj_t; value: plv_font_t;
  selector: cuint); cdecl; external;                                        { lv_obj_style_gen.h:2352 }

{ ---------------------------------------------------------------- display }

function lv_display_get_default: plv_display_t; cdecl; external;            { lv_display.h:114 }
function lv_display_get_horizontal_resolution(
  disp: plv_display_t): cint32; cdecl; external;                            { lv_display.h:183 }
function lv_display_get_vertical_resolution(
  disp: plv_display_t): cint32; cdecl; external;                            { lv_display.h:190 }

{ ------------------------------------------------------------------ fonts }

var
  { LV_FONT_DECLARE(lv_font_montserrat_14) - lv_font.h:295; const object
    in C, only ever referenced by address. Enabled in the lvgl-s31
    sdkconfig: 14 (default), 20, and since 2026-11-07 also 28 + 36 (user
    asked for bigger on-screen text; enabling a font = one Kconfig line +
    idf.py rebuild). }
  lv_font_montserrat_14: Byte; external;
  lv_font_montserrat_20: Byte; external;
  lv_font_montserrat_28: Byte; external;
  lv_font_montserrat_36: Byte; external;

implementation

function ColorMake(r, g, b: Byte): cuint;
begin
  Result := cuint(b) or (cuint(g) shl 8) or (cuint(r) shl 16);
end;

function ColorBlack: cuint;
begin
  Result := 0;
end;

function ColorWhite: cuint;
begin
  Result := $00FFFFFF;  { b=255 | g=255<<8 | r=255<<16 }
end;

end.
