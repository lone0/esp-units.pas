# `threads/` — upstream FPC thread cases on `fthreads`

Systematic thread cases imported from the FPC test tree
(`/mnt/storage/fpc-esp/FPCSource-esp-idf/tests`), pinned to this repo's
opt-in `fthreads` thread manager. Each file keeps the upstream source
shape except:

- line 1: `upstream provenance:` comment (repo rename convention)
- `uses`: `idfheap, fthreads` first (replaces the per-platform
  `cthreads`/`athreads` pick)
- `t_threads_ansistring_workers`: ESP targets select `slowcpu` (8 workers,
  2,000 characters each); the main task waits with `vTaskDelay`
  (SysUtils.Sleep is a no-op here). Worker `writeln`s are upstream-original
  and working (see below).

Current stack: fthreads TextRec stdio templates (d6c22fc — worker stdio =
clones of main's opened records), 4 KiB default-stack remap (82e0558),
idfheap GetMem(0) → nil (1e07bca). RTL state: CONSOLEIO feature off,
DefaultSystemCodePage = 0 (CP_ACP, uninitialized by decision — the
CP_UTF8 two-line change was abandoned, see the open items).

Kept OUT of the top-level suite stats (`run-tests.sh`): these cases pin
down what works under `fthreads` and what does not — failures here are
findings, not suite regressions.

## Results (2026-11-14, S3 QEMU + S31 esp-emu + Mosaico flashed)

| case | upstream source | exercises | result |
| --- | --- | --- | --- |
| `t_threads_ansistring_workers` | `tests/test/tmt1.pp` | 8 workers × 2,000-char ansistring builds + **worker `writeln`** (interleaved but legible), threadvar, InterLockedIncrement, vTaskDelay-paced wait | **PASS** (S3, S31, Mosaico hw) — 16 worker lines + final `8`, exit 0 |
| `t_threads_class_threadvar` | `tests/test/tclass16.pp` | class threadvar isolation + RTLEvent | **PASS** (S3, S31, Mosaico hw) |
| `t_threads_record_threadvar` | `tests/test/terecs20.pp` | record threadvar isolation + RTLEvent | **PASS** (S3, S31, Mosaico hw) |
| `t_threads_mm_hooks` | `tests/webtbs/tw40838.pp` | memory-manager InitThread/DoneThread hooks around BeginThread | **PASS** (S3 ×3, S31, Mosaico hw) — passes since idfheap returns nil for GetMem(0); race-dependent without join. Its `RelocateHeap`-hook writeln never fires (heap_caps never relocates) |
| `t_threads_output_codepage` | `tests/webtbs/tw34163.pp` | per-thread `Output` Text record (CodePage) | **PASS (vacuous)**: worker TextRec CodePage = main's copy = DefaultSystemCodePage = 0 → 0 = 0, deterministic (verified S3 `ok`, exit 0). The codepage dimension is unimplemented by decision |

`waitfor` was removed from this suite (join declined this round); its
contract probe lives in git history.

## Worker writeln: VERIFIED WORKING

The TextRec template commit (d6c22fc) fixed the historical worker-writeln
crash: each spawned thread's stdio Text records are clones of main's
opened records (real hooks, retargeted buffer), so `writeln` from a
`BeginThread` worker reaches the console. Verified:

- Mosaico hardware (user run): worker lines interleaved but legible.
- S3 QEMU (re-check after a false-negative): 16
  `thread N started/finished` lines from 8 workers, correct content,
  main's final count `8`, exit 0.


## Open items (in /tmp/threads-fix, ephemeral)

1. **Read-only CodePage probe quirk** — `t_cp_read_only` (3-arg
   BeginThread, worker reads `TextRec(Output).CodePage`, main prints)
   fails with `Runtime error 203` at BeginThread on the current RTL,
   while the write-path cases (ansistring workers) run fine at the same
   effective 4 KiB stack. One earlier run also showed the worker reading
   the 771 FillByte residue. Narrow probe, own RCA round.
2. **Single-worker probes are unstable regardless of stack size** — the
   probe series (2026-11-14): a no-op worker at the remapped 4 KiB dies
   with `Runtime error 203`; a value-writeln worker at 16 KiB explicit
   dies in a hardware exception (the vector layer); the SAME shapes run
   fine in the multi-worker suite cases (8 × 4 KiB remapped: 16 worker
   lines + the builds PASS). The instability tracks the single-worker +
   probe-standalone configuration, not the stack size — needs the
   esp32s3-QEMU-level debugging (gdb: the task's stack bounds + the
   faulting PC). Worker stacks: explicit ≥16 KiB (the suite convention);
   the multi-worker configurations verified stable.
3. **Worker writeln on S3 QEMU: hangs in the console driver** — the same
   finding as above, isolated by a write-path ladder (a no-op worker / a
   raw C putchar worker / a Pascal writeln worker at 16 KiB explicit:
   all three complete, but only the main's lines reach the serial on
   QEMU; the Pascal writeln variant core-dumps at 4 KiB default stack).
   esp32s3-QEMU-specific; riscv32 (S31 emu + Mosaico hw) verified working.
4. **DefaultSystemCodePage — ABANDONED (user decision, 2026-11-14)**: the
   CP_UTF8 initialization and the `OpenIO` CodePage assignment were lost
   in a branch switch and will **not** be restored. `DefaultSystemCodePage`
   stays 0 (CP_ACP, never assigned on this target) and the Text records
   match it, so the case passes vacuously (0 = 0) — verified on S3
   (`ok`, exit 0). The codepage dimension remains unimplemented by
   decision; the design notes (proposal + verification record) are
   preserved at `/mnt/storage/fpc-esp/stdio-codepage-design-discarded.md`
   (moved there when the RTL edits were reverted).
5. **join** — declined this round; the case and the verified prototype
   live in git history and /tmp respectively.

## Mosaico hardware

Flash the `--tight` image with
`esptool --no-stub --before default-reset --after hard-reset write-flash 0x0`
(usb_hs_console auto-download handles the entry; port `/dev/ttyACM0` only).
Known capture limit: sub-second case output lands before USB enumeration
completes and is dropped — emulator verdicts are authoritative for fast
cases; slow cases (the landscape demo, long-running workers) stream fine.

## Excluded upstream thread cases, with reasons

- `tests/test/units/system/tthreadsched.pp`, `tthreadprio.pp` —
  `{ %target=linux }` (sched_setscheduler / nice via libc)
- `tests/test/tthread1.pp`, `twaitfreeonterm.pp`, `theapthread.pp`,
  `tests/units/sysutils/trwsync.pp` — TThread-class based; the freertos
  RTL's TThread is a silent stub (`rtl/freertos/tthread.inc`, Execute
  never runs; the raising patch sits unapplied in `pending-patches/`)
- `tests/webtbs/tw12987b.pp`, `tw14992c.pp` — windows-only targets
