#!/bin/sh
# build.sh — cross-build a Pascal program for an ESP32-family SoC.
#
# INVARIANT (see ../AGENTS.md): fpc and esp-idf are EXTERNAL tools to this
# repo. This script never guesses where they live — set the env vars below.
#
# Usage:   scripts/build.sh [--soc esp32s3|esp32s31] [fpc options] <prog.pas>
#          scripts/build.sh prog.pas                 # default SoC: esp32s3
# Output:  prog.o / prog.elf / prog.bin / prog.img written next to the source.
#
# Required environment:
#   ESP_FPC_ROOT       fpc-cross install for *this* build — tree with
#                      lib/fpc/<ver>/ppcross{xtensa|riscv32} and lib/fpc/etc/fpc.cfg.
#                      Point it at the xtensa tree for esp32s3, the riscv32 tree
#                      for esp32s31 (or any future SoC). --soc only selects the
#                      binary name + MCU flags inside that root.
#   ESP_IDF_VERSION    IDF version string for -WP (e.g. 6.1)
#   ESP32_SDK_PROJECT  built ESP-IDF project (bootloader, sdkconfig, libesp_psram.a)
#
# Optional (else discovered from the toolchain fpc.cfg -Fl lines / IDF_PATH):
#   ESP_IDF_PATH       ESP-IDF root (esptool.py)
#   ESP_TOOLCHAIN_BIN  <xtensa|riscv32>-esp-elf/bin
#   ESP_PYTHON_BIN     python venv bin/ that can import esptool
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

need_env() {
  eval "v=\${$1:-}"
  if [ -z "$v" ]; then
    echo "error: $1 is not set" >&2
    exit 1
  fi
}

find_ppc() {
  # $1 = FPC_ROOT, $2 = binary name (ppcrossxtensa | ppcrossriscv32)
  root=$1
  name=$2
  found=
  for cand in "$root"/lib/fpc/*/"$name"; do
    if [ -x "$cand" ]; then
      if [ -n "$found" ]; then
        echo "error: multiple $name under $root/lib/fpc (set a single-version install)" >&2
        exit 1
      fi
      found=$cand
    fi
  done
  if [ -z "$found" ]; then
    echo "error: $name not found under $root/lib/fpc/*/ — is ESP_FPC_ROOT the right install for --soc?" >&2
    exit 1
  fi
  printf '%s\n' "$found"
}

soc=esp32s3
if [ "$1" = "--soc" ]; then
  [ $# -ge 2 ] || { echo "usage: $0 --soc <name> ..." >&2; exit 1; }
  soc="$2"; shift 2
fi

need_env ESP_FPC_ROOT
need_env ESP_IDF_VERSION
need_env ESP32_SDK_PROJECT
FPC_ROOT=$ESP_FPC_ROOT
IDF_VER=$ESP_IDF_VERSION
PRJ=$ESP32_SDK_PROJECT

# --- per-SoC table: MCU / compiler binary / binutils family only ------------
case "$soc" in
  esp32s3)
    PPC_NAME=ppcrossxtensa
    MCU=-WpESP32S3
    ESPTOOL_CHIP=esp32s3
    TOOLCHAIN_NAME=xtensa-esp-elf
    ;;
  esp32s31)
    PPC_NAME=ppcrossriscv32
    MCU=-WpESP32S31
    ESPTOOL_CHIP=esp32s31
    TOOLCHAIN_NAME=riscv32-esp-elf
    ;;
  *)
    echo "unknown SoC: $soc (known: esp32s3 esp32s31)" >&2; exit 1;;
esac

PPC=$(find_ppc "$FPC_ROOT" "$PPC_NAME")
[ -x "$PPC" ] || { echo "cross compiler missing: $PPC" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: $(basename $0) [--soc <name>] [fpc options] <prog.pas>" >&2; exit 1; }

# Discover binutils + IDF root from the toolchain's own fpc.cfg -Fl lines
# (env overrides win). No host path defaults.
CFG=$FPC_ROOT/lib/fpc/etc/fpc.cfg
[ -f "$CFG" ] || { echo "error: missing $CFG" >&2; exit 1; }
TC_MATCH=$(sed -n "s|^ *-Fl\\(.*/$TOOLCHAIN_NAME/[^/]*\\)/$TOOLCHAIN_NAME/.*|\\1|p" "$CFG" 2>/dev/null | head -1)
if [ -n "${ESP_TOOLCHAIN_BIN:-}" ]; then
  TC_BIN=$ESP_TOOLCHAIN_BIN
elif [ -n "$TC_MATCH" ]; then
  TC_BIN=$TC_MATCH/$TOOLCHAIN_NAME/bin
else
  TC_BIN=
fi
if [ -n "${ESP_IDF_PATH:-}" ]; then
  IDF_PATH=$ESP_IDF_PATH
else
  IDF_PATH=$(sed -n 's|^ *-Fl\(/.*/esp-idf[^/]*\)/.*|\1|p' "$CFG" 2>/dev/null | head -1)
fi
[ -d "$TC_BIN" ] || { echo "esp binutils not found (set ESP_TOOLCHAIN_BIN or -Fl …/$TOOLCHAIN_NAME/… in $CFG)" >&2; exit 1; }
[ -d "$IDF_PATH" ] || { echo "ESP-IDF root not found (set ESP_IDF_PATH or -Fl …/esp-idf… in $CFG)" >&2; exit 1; }
export PATH="$TC_BIN:$PATH" IDF_PATH

# esptool must be importable by the python the compiler invokes.
if [ -n "${ESP_PYTHON_BIN:-}" ]; then
  PYBIN=$ESP_PYTHON_BIN
else
  IDF_MAJOR_MINOR=$(basename "$IDF_PATH" | sed -n 's/^esp-idf-v\([0-9]*\.[0-9]*\).*$/\1/p')
  if [ -n "$IDF_MAJOR_MINOR" ]; then
    PYBIN=$(ls -d "$HOME"/.espressif/python_env/idf${IDF_MAJOR_MINOR}_*/bin 2>/dev/null | head -1)
  else
    PYBIN=
  fi
fi
[ -d "$PYBIN" ] || { echo "idf python venv not found (set ESP_PYTHON_BIN)" >&2; exit 1; }
export PATH="$PYBIN:$PATH"

# --- SPIRAM link closure ----------------------------------------------------
# When the SDK project was built WITH CONFIG_SPIRAM, its esp_system/freertos
# archives gain references to esp_psram_* symbols (libesp_psram.a). FPC only
# injects an extra archive when a USED unit carries {$linklib <n>,static}.
# idfheap carries {$linklib esp_psram,static} under -dESPSDK_SPIRAM.
CFGH=$PRJ/build/config/sdkconfig.h
if grep -aq '^#define CONFIG_SPIRAM 1' "$CFGH" 2>/dev/null; then
  PSRAM_LIBDIR=$PRJ/build/esp-idf/esp_psram
  [ -f "$PSRAM_LIBDIR/libesp_psram.a" ] || {
    echo "SPIRAM sdkconfig detected in $CFGH but $PSRAM_LIBDIR/libesp_psram.a is missing - rebuild the SDK project first" >&2
    exit 1
  }
  STAMP=$REPO/units/.idfheap-spiram-state-$soc
  if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$PSRAM_LIBDIR" ]; then
    rm -f "$REPO/units/idfheap.ppu" "$REPO/units/idfheap.o"
    printf '%s\n' "$PSRAM_LIBDIR" > "$STAMP"
  fi
  set -- -dESPSDK_SPIRAM "-Fl$PSRAM_LIBDIR" "$@"
fi

# -Tfreertos + -Wp<MCU> + -WP<IDF ver>; units/ via -Fu. Later options win.
exec "$PPC" -Tfreertos "$MCU" "-WP$IDF_VER" \
  "-Fu$REPO/units" "-Fu$REPO/units/espatomics" "$@"
