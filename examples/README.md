# examples/ — programs demonstrating how to use the units

Each program here is a small, complete demonstration of one unit from
`units/`. Unlike `tests/` (compiler regressions under the automated runner),
these are meant to be read first, then built and booted by hand.

Build/boot with the standard automation from the repo root:

```sh
scripts/build.sh examples/idfheap-smoke.pas      # → examples/idfheap-smoke.elf
scripts/run-qemu.sh examples/idfheap-smoke.elf   # serial console on stdout
```

| example | demonstrates | expected output (esp32s3) | pitfall |
|---|---|---|---|
| `idfheap-smoke.pas` | the `idfheap` unit in production shape: `GetMem`/`FreeMem`, sorted `TStringList` (the in-place-ReAllocMem contract), and a 50 000-slot dynamic array — all routed into the IDF pool; **every** printed pointer is classified by IDF's PSRAM-specific `esp_ptr_external_ram` (never by address ranges) | **SDK without SPIRAM:** `GetMem(4096) @3FCAxxxx -> internal SRAM`, `IDF pool: used=~27KB free=~343KB size=~370908`, `TStringList item string @3FCAxxxx -> internal SRAM`, `dynarray 500 slots @3FCAxxxx -> internal SRAM` (printed on location change only — one line, the buffer is reused by `realloc`), `dynarray content ok, big[99]=9801`, exit 0. **SDK with SPIRAM (QEMU octal PSRAM):** boot log shows `octal_psram:`/`esp_psram: Found 32MB PSRAM device`, then the same lines but `-> PSRAM` everywhere and a ~32 MB heap size | `uses idfheap` must be FIRST — not-first installs the empty static manager and the first allocation dies with `RunError 203`. `LocationOf` deliberately does not declare `esp_ptr_internal`: in IDF 5.x it is a static header inline, not a linkable symbol — "not external" *is* internal. The PSRAM variant additionally requires the SPIRAM link closure (see `units/README.md`); `scripts/build.sh` handles it automatically |

Note: with `CONFIG_SPIRAM_USE_MALLOC` even *small* allocations land in
PSRAM, because IDF reserves 32 KiB of internal SRAM for capability-tagged
internal allocations (`CONFIG_SPIRAM_MALLOC_RESERVE_INTERNAL`) — internal
free space under that threshold pushes default allocations to PSRAM.

Adding an example: keep it minimal and self-explaining, add a row here, and
give it the same `idfheap`-first rule if it allocates anything (see the repo
`AGENTS.md` ground rules).
