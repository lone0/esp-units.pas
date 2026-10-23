# trace-repro — diagnostics that need a `-dfpc_HEAPTRACE` RTL build

These probes only *compile* against an RTL built with `-dfpc_HEAPTRACE`
(add `-dfpc_HEAPTRACE` inside a rebuild of the rtl, recipe in the toolchain
workspace's AGENTS.md §9 step 5, variant d): the freertos heapmgr exposes a
guarded `HeapTraceEnable` procedure (rtl/freertos/heapmgr.pp) that echoes every
heap allocation/free to the console (`G` = get, `F` = free, `M` = entry into
InternalFreeMem, `W` = free-block header write, `Z` = terminal header write).
It is a pure diagnostic, guarded by `{$ifdef FPC_HEAPTRACE}`; the normal RTL
does not contain it.

`probe-tr-trace.pas` logs the final ledger before the crash and is the
regression demonstration for the now-SOLVED exit-teardown bug: with the
*unpatched* compiler (forward finalize table) its ledger showed the
`TEncoding.Default` singleton's chunk freed early at exit and later merge
header rewrites zeroing its VMT slot → `LoadProhibited 0x30`. With the
toolchain's 4-patch series applied (`xtensa-04-finalize-order.patch` in
particular, see the toolchain workspace), the same probe exits
`_haltproc exit code: 0` with a clean double-merge of the last two frees.

`probe-enc.pas` (one level up, in the suite dir) runs against the normal RTL —
it only reads `TEncoding.Default`'s memory and `IsStandardEncoding`, and is
kept in the suite as a PASS regression.
