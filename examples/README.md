# examples/ — programs demonstrating how to use the units

Each program here is a small, complete demonstration of one unit from
`units/`. Unlike `tests/` (compiler regressions under the automated runner),
these are meant to be read first, then built and booted by hand.

Build/boot with the standard automation from the repo root:

```sh
scripts/build.sh examples/idfheap-smoke.pas      # → examples/idfheap-smoke.elf
scripts/run-qemu.sh examples/idfheap-smoke.elf   # serial console on stdout

# Pascal + C example: one command; the extra --lib names are the LCD driver
# archives IDF does not link unless listed (see the pispigot-lcd row below)
scripts/build.sh examples/pispigot-lcd.pas --c examples/waveshare_lcd.c \
  --lib esp_hal_i2c --lib esp_lcd --lib esp_driver_i2c --lib esp_driver_spi \
  --lib esp_driver_gpio --lib log
```

| example | demonstrates | expected output (esp32s3) | pitfall |
|---|---|---|---|
| `idfheap-smoke.pas` | the `idfheap` unit in production shape: `GetMem`/`FreeMem`, sorted `TStringList` (the in-place-ReAllocMem contract), and a 50 000-slot dynamic array — all routed into the IDF pool; **every** printed pointer is classified by IDF's PSRAM-specific `esp_ptr_external_ram` (never by address ranges) | **SDK without SPIRAM:** `GetMem(4096) @3FCAxxxx -> internal SRAM`, `IDF pool: used=~27KB free=~343KB size=~370908`, `TStringList item string @3FCAxxxx -> internal SRAM`, `dynarray 500 slots @3FCAxxxx -> internal SRAM` (printed on location change only — one line, the buffer is reused by `realloc`), `dynarray content ok, big[99]=9801`, exit 0. **SDK with SPIRAM (QEMU octal PSRAM):** boot log shows `octal_psram:`/`esp_psram: Found 32MB PSRAM device`, then the same lines but `-> PSRAM` everywhere and a ~32 MB heap size | `uses idfheap` must be FIRST — not-first installs the empty static manager and the first allocation dies with `RunError 203`. `LocationOf` deliberately does not declare `esp_ptr_internal`: in IDF 5.x it is a static header inline, not a linkable symbol — "not external" *is* internal. The PSRAM variant additionally requires the SPIRAM link closure (see `units/README.md`); `scripts/build.sh` handles it automatically |
| `leibniz.pas` | a timing pattern: a 10⁶-iteration Leibniz series with `esp_timer_get_time` (µs, monotonic, declared as an external — `esp_timer` is already in the RTL's link list) bracketing the loop; the header line also prints the float type via `PTypeInfo(TypeInfo(pi))^.Name` | `Leibniz Pi rounds 1000000 of type Double`, `rounds: 1000000`, `loop: <n> us = <n> ms`, exit 0. Under QEMU on this host: **`double` ≈ 8.8–9.7 s**, and `single` (the `{single;}` alternative) ≈ 1.05 s — the S3 has no double-precision FPU, so `double` is software-emulated | the numbers are emulator wall-clock, not board speed; read them as *relative* measures. `idfheap` **must** be first: formatting a float in `writeln` allocates, and without the IDF heap manager it dies in FPC's static heap with `RunError 203` (reproduced here before the unit was added) |
| `pispigot-lcd.pas` (+ `waveshare_lcd.c`) | Pascal↔C in one binary: the spigot algorithm collects the digit stream it would print into a global buffer during the timed region (no I/O inside the timer), then after the timer stops feeds the first screenful to `waveshare_lcd.c`'s ST7796 SPI LCD console (AXP2101 power, TCA9554 expander, esp_lcd ST7789 driver, FreeRTOS render task, `/dev/lcdcon` VFS): `Pi = ` + the first 795 digits = the 40x20 console exactly, no scrolling (the 5001-digit buffer stays intact and was byte-verified against the C twin). Rows are paced (`lcd_write` + `vTaskDelay(5)` per 40-char row — the render task drains ~128 chars per ~110 ms frame and `console_enqueue` drops everything after the first failed send, so an unpaced write loses bytes) with a 1 s linger before exit — and reports on serial: `Time: <n> us`, `digits: <count>`, `lcd dropped bytes: <n>`. Built in one command by `build.sh --c` — the C object is compiled with IDF's own recorded compile flags and linked with the Pascal one. 5001 digits for n=5000, byte-exact against the C twin in hello-s3 (see the instruction-level analysis comment inside `pispigot-lcd.pas`); board (160 MHz) timing ≈ 17.38 s at -O2 vs 10.88 s for the C twin | serial: the IDF boot log, `Time:`/`digits:`/`lcd dropped bytes: 0`, then `_haltproc called, exit code: 0`; the LCD holds the static first screen (`Pi = 0314159265...`). `dropped bytes: 0` is the no-loss verdict for what the screen shows; the full 5001-digit stream was verified byte-exact vs the reference in an earlier scrolling build (106 ESP_LOGI scroll rows = digits 36..4275) — that check needs the scrolling display | `idfheap` must be first (`IntToStr` allocates). The C module's driver archives are never linked by default — pass `--lib esp_hal_i2c --lib esp_lcd --lib esp_driver_i2c --lib esp_driver_spi --lib esp_driver_gpio --lib log`; the SDK project must build those components (they are in `waveshare-s3`'s REQUIRES/PRIV_REQUIRES). QEMU models neither the LCD nor I2C: the render task never runs, so rows beyond the 2 KiB queue capacity are dropped there (the paced dump still completes in ~7 s; treat the `Time:` line + exit 0 as the QEMU verdict). Build with `-O2` when comparing against the C twin |

Note: with `CONFIG_SPIRAM_USE_MALLOC` even *small* allocations land in
PSRAM, because IDF reserves 32 KiB of internal SRAM for capability-tagged
internal allocations (`CONFIG_SPIRAM_MALLOC_RESERVE_INTERNAL`) — internal
free space under that threshold pushes default allocations to PSRAM.

Adding an example: keep it minimal and self-explaining, add a row here, and
give it the same `idfheap`-first rule if it allocates anything (see the repo
`AGENTS.md` ground rules).
