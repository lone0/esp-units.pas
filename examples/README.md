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
| `idfheap-smoke.pas` | the `idfheap` unit in production shape: `GetMem`/`FreeMem`, sorted `TStringList` (the in-place-ReAllocMem contract), and a 50 000-slot dynamic array — all routed into the IDF pool | `GetMem(4096) @3FCAxxxx`, `IDF pool: used=~27KB free=~343KB size=~370908`, `TStringList 100 items sorted; last item length 9`, `dynarray 100 x 500 slots ok, big[99]=9801`, exit 0 | `uses idfheap` must be FIRST — not-first installs the empty static manager and the first allocation dies with `RunError 203` |

Adding an example: keep it minimal and self-explaining, add a row here, and
give it the same `idfheap`-first rule if it allocates anything (see the repo
`AGENTS.md` ground rules).
