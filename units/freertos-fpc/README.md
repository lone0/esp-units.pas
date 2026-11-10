# `freertos-fpc` — optional Delphi-style threads on ESP-IDF

Application-side supplement. The FPC freertos RTL keeps its **no-thread /
stub** contract; programs that want `BeginThread` / `TThread`-style APIs
`uses` this package explicitly.

| Unit | Role |
| --- | --- |
| `esp_task.pp` | Thin IDF 6.x task + TLS bindings (`xTaskCreatePinnedToCore`, …) |
| `esp_semphr.pp` | Mutex / binary semaphore wrappers over linkable queue symbols |
| `fthreads.pp` | FPC `TThreadManager` on those bindings + `idfheap` |

Provenance: adapted from [ccrause/fpc-esp-freertos](https://github.com/ccrause/fpc-esp-freertos)
`freertos-fpc/fthreads.pp` (branch `esp-idf-v5.5`).

**Usage:** `uses idfheap, fthreads, …;` — `idfheap` first, `fthreads` before
`classes`. See `examples/fpcthreads/`.
