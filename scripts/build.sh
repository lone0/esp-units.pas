#!/bin/sh
# build.sh — cross-build a Pascal program for an ESP32-family SoC.
#
# INVARIANT (see ../AGENTS.md): fpc and esp-idf are EXTERNAL tools to this
# repo. This script only records where they live and which SoC to target.
#
# Usage:   scripts/build.sh [--soc esp32s3|esp32c3] [fpc options] <prog.pas>
#          scripts/build.sh prog.pas                 # default SoC: esp32s3
# Output:  prog.o / prog.elf / prog.bin / prog.img written next to the source.
#
# Environment overrides (all optional):
#   ESP_FPC_ROOT      root of the xtensa (esp32s2/s3/classic) fpc-cross install
#                     (default: the sibling toolchain workspace on this machine)
#   ESP_FPC_ROOT_C3   same, for the riscv32 c3-class toolchain (required for
#                     esp32c3 builds; no default install exists yet)
#   ESP_IDF_VERSION   ESP-IDF version your toolchain ships an espidf_<ver>
#                     interface unit for (default 5.2.8 -> espidf_50200)
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

soc=esp32s3
if [ "$1" = "--soc" ]; then
  [ $# -ge 2 ] || { echo "usage: $0 --soc <name> ..." >&2; exit 1; }
  soc="$2"; shift 2
fi

# --- per-SoC table (add new SoCs here; everything below reads this table) ---
case "$soc" in
  esp32s3)
    FPC_ROOT=${ESP_FPC_ROOT:-/mnt/storage/rewind-fpc-esp/fpc-cross}
    PPC=$FPC_ROOT/lib/fpc/3.3.1/ppcrossxtensa      # xtensa lx7 (hf) cross compiler
    MCU=-WpESP32S3
    QEMU_MACHINE=esp32s3
    ESPTOOL_CHIP=esp32s3
    TOOLCHAIN_NAME=xtensa-esp-elf
    ;;
  esp32c3)
    # riscv32 cross compiler: declared external prerequisite; the toolchain
    # lives wherever ESP_FPC_ROOT_C3 points (not installed in the reference
    # workspace yet). The espatomics unit already carries an rv32a backend.
    FPC_ROOT=${ESP_FPC_ROOT_C3:?no riscv32 toolchain installed - set ESP_FPC_ROOT_C3}
    PPC=$FPC_ROOT/lib/fpc/3.3.1/ppcrossriscv32
    MCU=-WpESP32C3
    QEMU_MACHINE=esp32c3
    ESPTOOL_CHIP=esp32c3
    TOOLCHAIN_NAME=riscv32-esp-elf
    ;;
  *)
    echo "unknown SoC: $soc (known: esp32s3 esp32c3)" >&2; exit 1;;
esac

[ -x "$PPC" ] || { echo "cross compiler missing: $PPC" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: $(basename $0) [--soc <name>] [fpc options] <prog.pas>" >&2; exit 1; }

# The compiler shells out to binutils (<prefix>as/ld) by name and, at link
# time, to the IDF's esptool.py — discover both paths FROM THE TOOLCHAIN'S
# OWN fpc.cfg (so a relocated toolchain keeps working); env overrides win.
#   binutils:  -Fl <...>/<toolchain>/<ver>/<toolchain>/lib/...  -> its bin/
#   IDF root:  -Fl <...>/esp-idf-v<X>/components/...            -> its root
CFG=$FPC_ROOT/lib/fpc/etc/fpc.cfg
TC_MATCH=$(sed -n "s|^ *-Fl\\(.*/$TOOLCHAIN_NAME/[^/]*\\)/$TOOLCHAIN_NAME/.*|\\1|p" "$CFG" 2>/dev/null | head -1)
TC_BIN=${ESP_TOOLCHAIN_BIN:-$TC_MATCH/$TOOLCHAIN_NAME/bin}
IDF_PATH=${ESP_IDF_PATH:-$(sed -n 's|^ *-Fl\(/.*/esp-idf-v\?[0-9.]*\)/.*|\1|p' "$CFG" 2>/dev/null | head -1)}
[ -d "$TC_BIN" ] || { echo "esp binutils not found (looked via $CFG; set ESP_TOOLCHAIN_BIN)" >&2; exit 1; }
[ -d "$IDF_PATH" ] || { echo "ESP-IDF root not found (looked via $CFG; set ESP_IDF_PATH)" >&2; exit 1; }
export PATH="$TC_BIN:$PATH" IDF_PATH

# esptool must be importable by the `python` the compiler invokes: put the
# matching IDF python venv first on PATH (idf<MAJOR.MINOR> derived from the
# IDF root's version); ESP_PYTHON_BIN overrides.
IDF_MAJOR_MINOR=$(basename "$IDF_PATH" | sed -n 's/^esp-idf-v\([0-9]*\.[0-9]*\).*$/\1/p')
PYBIN=${ESP_PYTHON_BIN:-$(ls -d "$HOME"/.espressif/python_env/idf${IDF_MAJOR_MINOR}_*/bin 2>/dev/null | head -1)}
[ -d "$PYBIN" ] || { echo "idf python venv not found for IDF $IDF_MAJOR_MINOR (set ESP_PYTHON_BIN)" >&2; exit 1; }
export PATH="$PYBIN:$PATH"

IDF_VER=${ESP_IDF_VERSION:-5.2.8}

# Notes:
#  - -Tfreertos + -Wp<MCU> + -WP<IDF ver>: the freertos target, chip id and
#    the espidf interface-unit generation (the toolchain's fpc.cfg carries the
#    linker search paths into the IDF project build dir).
#  - Units shipped in units/ (idfheap) and units/<subdir>/: no per-program
#    -Fu ever needed.
#  - Later options win over the fixed ones, so per-program overrides
#    (e.g. -Ch1024) keep working, exactly like the old compile-s3.sh.
exec "$PPC" -Tfreertos "$MCU" "-WP$IDF_VER" \
  "-Fu$REPO/units" "-Fu$REPO/units/espatomics" "$@"
