# `fpcthreads` — Delphi-style threads via `fthreads`

Application-side demo of `units/freertos-fpc/fthreads.pp`: Pascal
`BeginThread` / critical sections / `RTLEvent` on ESP-IDF FreeRTOS, without
changing the freertos RTL stubs in FPCSource.

Adapted from [ccrause/fpc-esp-freertos `examples/fpcthreads`](https://github.com/ccrause/fpc-esp-freertos/tree/esp-idf-v5.5/examples/fpcthreads)
for IDF 6.1 + `idfheap`, trimmed for QEMU / esp-emu (finite work, no GPIO,
no run-time stats).

## Requires

- ESP-IDF project with `CONFIG_FREERTOS_THREAD_LOCAL_STORAGE_POINTERS >= 1`
  (default on the S3/S31 build trees used here).
- `idfheap` then `fthreads` early in `uses` (before `classes`).

## Build & run

```sh
export ESP_FPC_ROOT=$HOME/fpc-cross-s3 \
       ESP32_SDK_PROJECT=$HOME/idf-build-s3 \
       ESP_IDF_PATH=$HOME/esp/esp-idf-v6.1 \
       ESP_IDF_VERSION=6.1
scripts/build.sh --soc esp32s3 examples/fpcthreads/fpcthreads.pas
scripts/run-qemu.sh --soc esp32s3 examples/fpcthreads/fpcthreads.bin

export ESP_FPC_ROOT=$HOME/fpc-cross-s31 ESP32_SDK_PROJECT=$HOME/idf-build-s31
scripts/build.sh --soc esp32s31 examples/fpcthreads/fpcthreads.pas
scripts/run-esp-emu.sh --soc esp32s31 examples/fpcthreads/fpcthreads.bin
```

Success marker: `FTHREADS_DONE` (and `shared=200` for two workers × 100).
