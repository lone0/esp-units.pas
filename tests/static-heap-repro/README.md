# probe-idfmm — the mid-run memory-manager hot-swap probe

`../idfheap-smoke.pas` (suite) demonstrates the *production* routing:
`idfheap` installed FIRST in uses, before any allocation happens.

This probe demonstrates the *other* guarantee: an IDF-pool
(`heap_caps_*`-backed) `TMemoryManager` can be installed MID-RUN - after
sysutils/classes have already initialized on the default static-heap
manager - and everything still works, PROVIDED ownership stays consistent:
pre-swap blocks owned by the static heap are delegated back to it
(`FreeMem/FreeMemSize/ReAllocMem/MemSize` range-check against
`__fpc_initialheap` + the `__heapsize` const) because unit-init objects
(teardown's `TThreadList`, a `TThreadList` inner list with capacity) must
be freed by the manager that allocated them; freeing them with
`heap_caps_free` aborts in IDF's multi-heap (`assert failed:
<cached disabled>`).

It therefore REQUIRES a static heap, and the toolchain's fpc.cfg no longer
carries `-Ch` (opt-in world: `idfheap` or explicit `-Ch`). Compile with:

    ../scripts/build.sh -Ch65536 probe-idfmm.pas
    timeout 15 ../scripts/run-qemu.sh "$PWD/probe-idfmm.elf"

Expected output:

    alloc @3FC9Cxxx static block          (inside __fpc_initialheap)
    alloc @3FCB3xxx IDF pool; MemSize=4096 (IDF pool 3FCADxxx..)
    TStringList 100 items sorted; last length 9
    dynarray 100 x 500 slots ok, big[99]=9801
    idf-routed memory manager OK
    _haltproc called, exit code: 0

Historical note: this probe is what surfaced the missing
`InitInternational` in the freertos sysutils (nil widestringmanager compare
procs -> PC=0 in `TStringList.Sort`) and the `ReAllocMem(var p)`
write-back contract (`p := result`, or `TFPList.SetCapacity` dies with
`FList=nil`):
