# Zone-2/3 threading-RTL contract demos (freertos)

These programs pin down the freertos RTL threading-stub contract:

  * **Benign for unit init/teardown**: `BasicEvent*Create` / `RTLEvent*Create`
    return nil (install/teardown housekeeping of `Classes.CommonInit` /
    `TMultiReadExclusiveWriteSynchronizer.Create` — it even *resets* its event
    at construction — must not die); `*destroy` and set/reset are no-ops;
    critical sections are upstream's own single-task no-ops.
  * **Loud on explicit use**:
    - *waiting* (`BasicEventWaitFor`, `RTLEventWaitFor*`) and the whole
      thread-creation/vartvar surface keep `NoThreadError` → `RunError(232)`;
    - `SyncObjs.TEvent.Create` raises `ESyncObjectException` (the FCL itself
      rejects a nil event handle);
    - `TThread.Create` raises an exception since `rtl/freertos/tthread.inc`'s
      upstream stub would otherwise *silently pretend* to thread
      ("This file is only a stub, and will not work!" warning upstream).

They are kept OUT of the top-level suite: `run-tests.sh` classifies any
`Runtime error`/panic as CRASH, and here the failure is the *designed,
correct* outcome. Run individually:

    ../scripts/build.sh <prog>.pas
    timeout 8 ../scripts/run-qemu.sh "$PWD/<prog>.elf"

| program               | expected outcome |
|-----------------------|------------------|
| `t_cs_noop.pas`       | PASS, prints `cs ok` — uncontended CS no-op is *correct* for a single task |
| `t_event_waitfor.pas` | prints `thread use blocked, as designed: ESyncObjectException` — **loud, by design** |
| `t_thread_create.pas` | prints `thread use blocked, as designed: Exception` — **loud, by design** |
