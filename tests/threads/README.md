# `threads/` — upstream FPC thread cases on `fthreads`

Systematic thread cases imported from the FPC test tree
(`/mnt/storage/fpc-esp/FPCSource-esp-idf/tests`), pinned to this repo's
opt-in `fthreads` thread manager. Each file keeps the upstream source
shape except:

- line 1: `upstream provenance:` comment (repo rename convention)
- `uses`: `idfheap, fthreads` first (replaces the per-platform
  `cthreads`/`athreads` pick)
- `t_threads_ansistring_workers`: both ESP CPUs select `slowcpu` (8 workers,
  2,000 characters each); workers use 16 KiB stacks and the main task delays
  one FreeRTOS tick while waiting. Worker `writeln`s are omitted because the
  shared Text output is not safe for concurrent writes.

Kept OUT of the top-level suite stats (`run-tests.sh`): the point of
these cases is to pin down what works under `fthreads` and what does
not — failures here are findings, not suite regressions.

Two cases are **PLANNED FAILURES (subsystem not implemented)**, marked as
such in their file headers: `t_threads_waitfor_exitcode` (no join in the
RTL or fthreads) and `t_threads_output_codepage` (no per-thread stdio /
CodePage initialization in the freertos RTL). Their deterministic failures
are the documentation of those gaps — do not "fix" the cases; implement
the subsystems (proposals in /tmp/threads-fix) or leave them as contract
probes.

Run (S3 / S31):

```sh
. /mnt/storage/fpc-cross/esp-cfg/env-6.1.sh
esp-env-esp32s3 && export ESP32_SDK_PROJECT=/mnt/storage/fpc-esp/hello-s3
scripts/build.sh tests/threads/<case>.pp
timeout 20 scripts/run-qemu.sh tests/threads/<case>.elf
esp-env-esp32s31        # esp-emu exits at _haltproc
scripts/build.sh --soc esp32s31 tests/threads/<case>.pp
timeout 20 scripts/run-esp-emu.sh --soc esp32s31 tests/threads/<case>.elf
```

Mosaico hardware: flash the `--tight` image with
`esptool --no-stub --before default-reset --after hard-reset write-flash 0x0`
(usb_hs_console auto-download handles the entry; port `/dev/ttyACM0` only).

| case | upstream source | exercises | result with 7064144+431cf88 (2026-11-13) | remaining gap |
| --- | --- | --- | --- | --- |
| `t_threads_ansistring_workers` | `tests/test/tmt1.pp` | 8 threads × 16 KiB stacks, ansistring heap in workers, threadvar, InterLockedIncrement, vTaskDelay-paced join | **PASS** (S3, S31, Mosaico flashed) | the on-disk form carries MCU adaptations (threadcount 8, explicit stacks, worker writeln removed — worker writeln is unsafe, see below) |
| `t_threads_class_threadvar` | `tests/test/tclass16.pp` | class threadvar isolation + RTLEvent | **PASS** (S3, S31; Mosaico flashed, output pre-enumeration) | — |
| `t_threads_record_threadvar` | `tests/test/terecs20.pp` | record threadvar isolation + RTLEvent | **PASS** (S3, S31; Mosaico flashed, output pre-enumeration) | — |
| `t_threads_waitfor_exitcode` | `tests/test/units/system/twaitthread.pp` | WaitForThreadTerminate exit-code semantics (#16492) | **PLANNED FAILURE**: `exit code 1, expected 42` → halt(2) (S3, S31, **Mosaico captured**) | subsystem not implemented: no join in the RTL **or** fthreads — `SysWaitForThreadTerminate` stub returns 1; join prototype verified in /tmp, awaiting review |
| `t_threads_output_codepage` | `tests/webtbs/tw34163.pp` | per-thread `Output` Text record (CodePage) | **PLANNED FAILURE**: `got 771` (= $0303, the FillByte(3) TLS residue) → halt(1) (S3, S31) | subsystem not implemented: the freertos RTL has `FPC_HAS_FEATURE_CONSOLEIO` **off** (`-SfCONSOLEIO` commented in system.cfg) so `InitThread` never runs `SysInitStdio` for workers — their stdio Text records are raw TLS bytes; and `OpenIO` never assigns CodePage. Two-part RTL patch proposed in /tmp |
| `t_threads_mm_hooks` | `tests/webtbs/tw40838.pp` | memory-manager InitThread/DoneThread hooks around BeginThread | **PASS** (S3 ×3, S31, Mosaico flashed) | passes since idfheap returns nil for GetMem(0) — previously the worker's `getmem(0)`→RunError(203) wrote through its uninitialized TextRec (same root cause as the output_codepage/worker-writeln crashes). Without join the pass is race-dependent (worker must finish before main checks the flags) |

Worker-side `writeln` (tmt1's original design) currently crashes with
LoadProhibited for the same reason: the worker's stdio Text records are raw
TLS bytes until the CONSOLEIO feature is enabled and the RTL is rebuilt.
Worker-side heap allocation itself is fine (`t_worker_alloc_clean` probe:
getmem(16)+freemem from a worker → ALLOC-OK, S31).
| --- | --- | --- | --- | --- |
| `t_threads_ansistring_workers` | `tests/test/tmt1.pp` | ESP targets: 8 workers × 2,000 ansistring appends, 16 KiB stacks, threadvar, InterLockedIncrement, one-tick wait | PASS: `8` on S3 QEMU and S31 esp-emu; Mosaico CDC captured `8` and `_haltproc` exit 0 (capture used a delay after workers completed) | Concurrent worker `writeln` was unsafe; `SysUtils.Sleep` is a no-op on FreeRTOS, so the test uses `vTaskDelay` |
| `t_threads_class_threadvar` | `tests/test/tclass16.pp` | class threadvar isolation + RTLEvent | CRASH: `Runtime error 203` on S31 esp-emu and Mosaico | `BeginThread` passes stack size 0, rejected by `xTaskCreate`; explicit 16 KiB stack passes with the /tmp fix set |
| `t_threads_record_threadvar` | `tests/test/terecs20.pp` | record threadvar isolation + RTLEvent | CRASH: `Runtime error 203` on S31 esp-emu and Mosaico | `BeginThread` passes stack size 0, rejected by `xTaskCreate`; explicit 16 KiB stack passes with the /tmp fix set |
| `t_threads_waitfor_exitcode` | `tests/test/units/system/twaitthread.pp` | WaitForThreadTerminate exit-code semantics (#16492) | CRASH: `Runtime error 203` | F1 + F2 (no join) — **passes with the /tmp fix set** (16 KiB stack + join prototype) |
| `t_threads_output_codepage` | `tests/webtbs/tw34163.pp` | per-thread `Output` Text record CodePage re-init | CRASH: `Runtime error 203` | F1 + F2 + F4 — after stack+join fixes it still fails with `got 771` (needs the consoleio patch) |
| `t_threads_mm_hooks` | `tests/webtbs/tw40838.pp` | memory-manager InitThread/DoneThread hooks | CRASH: `Runtime error 203` (anonymous-function overload → DefaultStackSize 4 MiB); post-4KiB-remap: S31 `Stack protection fault` boot loop in task fpc-1, S3 halt(2) | F1 (4 MiB default, fixed by 7064144's remap) + F3 (the worker does getmem — crashes at any stack size) + F2 (no join: S3 reaches the donecalled check before the worker finishes) |

All findings, patch proposals and the join prototype live in `/tmp/threads-fix/`
(`FINDINGS.md`, `fthreads-join-prototype.diff`, `patches/`, `cases/`) — nothing
was applied to the working tree; review before landing any of it.
| --- | --- | --- | --- |
| `t_threads_ansistring_workers` | `tests/test/tmt1.pp` | ESP-target slowcpu workload: 8 workers × 2,000 ansistring appends, 16 KiB stack, threadvar, InterLockedIncrement | PASS (`8`) on S3 QEMU + S31 esp-emu |
| `t_threads_class_threadvar` | `tests/test/tclass16.pp` | class threadvar isolation + RTLEvent handoff | PASS (`Ok`) |
| `t_threads_record_threadvar` | `tests/test/terecs20.pp` | record (advancedrecords) threadvar isolation + RTLEvent | PASS (`Ok`) |
| `t_threads_waitfor_exitcode` | `tests/test/units/system/twaitthread.pp` | WaitForThreadTerminate exit-code semantics (#16492) | known FAIL (`exit code 1, expected 42`): fthreads has no join — SysWaitForThreadTerminate is a stub |
| `t_threads_output_codepage` | `tests/webtbs/tw34163.pp` | per-thread `Output` Text record (CodePage re-init in the worker) | PASS (`ok`) — probes SysInitStdio on the worker's TLS |
| `t_threads_mm_hooks` | `tests/webtbs/tw40838.pp` | memory-manager InitThread/DoneThread hooks firing on BeginThread | expected FAIL (RunError 203): upstream passes stack size 0, which FreeRTOS xTaskCreate rejects — needs a 0→default fallback in fthreads |

Excluded upstream thread cases, with reasons:

- `tests/test/units/system/tthreadsched.pp`, `tthreadprio.pp` —
  `{ %target=linux }` (sched_setscheduler / nice via libc)
- `tests/test/tthread1.pp`, `twaitfreeonterm.pp`, `theapthread.pp`,
  `tests/units/sysutils/trwsync.pp` — TThread-class based; the freertos
  RTL's TThread is a silent stub (`rtl/freertos/tthread.inc`, Execute
  never runs; the raising patch sits unapplied in `pending-patches/`)
- `tests/webtbs/tw12987b.pp`, `tw14992c.pp` — windows-only targets
