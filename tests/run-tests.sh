#!/bin/bash
# FPC freertos regression-test runner (subset of FPC trunk tests/webtbs).
#
# For each *.pas in this dir: cross-compile via ../scripts/build.sh,
# boot under QEMU (15 s cap), classify the serial log:
#   PASS     - no Guru Meditation / panic / backtrace / "Runtime error"
#   CRASH    - any of the above seen (detail: implicated line)
#   COMPFAIL - program did not compile (unit missing / feature mismatch)
#
# Usage:  ./run-tests.sh              # all tests
#         ./run-tests.sh 't_math*.pas'  # glob subset
cd "$(dirname "$0")" || exit 1
CRX='Guru|panic|Backtrace|Runtime error|SIGILL|LoadProhibited|StoreProhibited'
printf '%-14s %-9s %s\n' TEST VERDICT DETAIL
for f in ${1:-*.pas}; do
    [ -f "$f" ] || continue
    case "$f" in run-tests.sh) continue;; esac
    n="${f%.pas}"
    rm -f "$n.o" "$n.ppu" "$n.elf" "$n.bin" "$n.img" "$n.flash.img" "$n.qemu.log"
    if ! ../scripts/build.sh "$f" >"$n.clog" 2>&1; then
        printf '%-14s %-9s %s\n' "$n" COMPFAIL "$(grep -aE 'Fatal:|Error:' "$n.clog" | head -1 | cut -c1-60)"
        continue
    fi
    # u_* sources are units: compile-only fixtures (a unit builds to .ppu/.o,
    # never to an .elf, so there is nothing to boot - verbatim trunk shape).
    if [ "${n#u_}" != "$n" ]; then
        rm -f "$n.ppu"
        printf '%-14s %-9s %s\n' "$n" COMPILE-ONLY "ok"
        continue
    fi
    timeout 15 ../scripts/run-qemu.sh "$PWD/$n.elf" >"$n.qemu.log" 2>&1
    if grep -aqE "$CRX" "$n.qemu.log"; then
        printf '%-14s %-9s %s\n' "$n" CRASH \
          "$(grep -aE "$CRX" "$n.qemu.log" | head -1 | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-50)"
    else
        h=$(grep -a '_haltproc called, exit code:' "$n.qemu.log" | tail -1 | sed 's/.*exit code:/exit:/')
        if [ -z "$h" ]; then
          last=$(sed 's/\x1b\[[0-9;]*m//g' "$n.qemu.log" \
                 | grep -av '^[-\[]\|^ESP-ROM\|^rst:\|^load:\|^entry\|^SPIWP\|^mode:\|^Build:\|^Adding\|^error: no such' \
                 | tail -1 | cut -c1-40)
          h="${last:-no output}"
        fi
        printf '%-14s %-9s %s\n' "$n" PASS "$h"
    fi
done
