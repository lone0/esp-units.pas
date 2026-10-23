#!/bin/sh
# run-qemu.sh — boot a Pascal/IDF app in the Espressif QEMU, serial console
# on stdout, until the emulator exits (-no-reboot). Test runners cap the
# wall-clock with `timeout`.
#
# Usage:   scripts/run-qemu.sh [--soc esp32s3] <prog.elf|prog.bin|prog.flash.img>
#
# esp32s31: QEMU has no machine for this SoC yet. Use scripts/run-esp-emu.sh.
#
# Required environment:
#   ESP32_SDK_PROJECT  built ESP-IDF project (sdkconfig / PSRAM boot recipe;
#                      also required by mkflash.sh)
#   ESP_IDF_PATH or ESP_PYTHON_BIN  — for mkflash.sh / esptool
#
# Optional:
#   ESP_QEMU           path to qemu-system-xtensa (else searched on PATH, then
#                      under $HOME/.espressif/tools)
set -e

need_env() {
  eval "v=\${$1:-}"
  if [ -z "$v" ]; then
    echo "error: $1 is not set" >&2
    exit 1
  fi
}

soc=esp32s3
if [ "$1" = "--soc" ]; then
  [ $# -ge 2 ] || { echo "usage: $0 --soc <soc> <elf|bin|img>" >&2; exit 1; }
  soc="$2"; shift 2
fi

case "$soc" in
  esp32s3)  QEMU_MACHINE=esp32s3; QEMU_BIN=qemu-system-xtensa ;;
  esp32s31)
    echo "error: --soc esp32s31 is not supported by QEMU yet." >&2
    echo "       use: $(dirname -- "$0")/run-esp-emu.sh [--soc esp32s31] <elf|bin|img>" >&2
    exit 1
    ;;
  *) echo "unknown SoC: $soc (known: esp32s3; esp32s31 → run-esp-emu.sh)" >&2; exit 1;;
esac

FILE=${1:?usage: $(basename $0) [--soc <soc>] <elf|bin|img>}
case "$FILE" in /*) ;; *) FILE="$(pwd)/$FILE" ;; esac
[ -f "$FILE" ] || { echo "error: no such file: $FILE" >&2; exit 1; }

need_env ESP32_SDK_PROJECT
PRJ=$ESP32_SDK_PROJECT

IMG=$("$(dirname -- "$0")/mkflash.sh" --soc "$soc" "$FILE")

if [ -n "${ESP_QEMU:-}" ]; then
  QEMU=$ESP_QEMU
elif command -v "$QEMU_BIN" >/dev/null 2>&1; then
  QEMU=$(command -v "$QEMU_BIN")
else
  QEMU=$(find "$HOME"/.espressif/tools -name "$QEMU_BIN" -type f 2>/dev/null | head -1)
fi
[ -n "$QEMU" ] && [ -x "$QEMU" ] || {
  echo "error: $QEMU_BIN not found (set ESP_QEMU)" >&2
  exit 1
}

CFGH=$PRJ/build/config/sdkconfig.h

# SPIRAM sdkconfig ⇒ PSRAM-capable QEMU boot (idf.py qemu recipe).
if grep -aq '^#define CONFIG_SPIRAM 1' "$CFGH" 2>/dev/null; then
  [ -f "$PRJ/build/qemu_efuse.bin" ] || {
    python3 - "$PRJ/build/qemu_efuse.bin" <<'PYEOF' || exit 1
import sys
b = bytearray(1024)
b[38] = 0x0c
open(sys.argv[1], 'wb').write(b)
PYEOF
  }
  QEMU_ARGS="-M $QEMU_MACHINE -m 32M \
-drive file=$IMG,if=mtd,format=raw \
-drive file=$PRJ/build/qemu_efuse.bin,if=none,format=raw,id=efuse \
-global driver=nvram.$QEMU_MACHINE.efuse,property=drive,value=efuse \
-global driver=timer.$QEMU_MACHINE.timg,property=wdt_disable,value=true"
  grep -aq '^#define CONFIG_SPIRAM_MODE_OCT 1' "$CFGH" && \
    QEMU_ARGS="$QEMU_ARGS -global driver=ssi_psram,property=is_octal,value=true"
else
  QEMU_ARGS="-M $QEMU_MACHINE -drive file=$IMG,if=mtd,format=raw"
fi

GFXDEV=$("$QEMU" -M "$QEMU_MACHINE" -device help 2>/dev/null \
         | grep -oE '"esp32[a-z0-9_-]*(lcd|display)[a-z0-9_-]*"' | head -1 | tr -d '"')
if [ -n "$GFXDEV" ]; then
  echo "--- booting with graphics device: $GFXDEV"
  exec "$QEMU" $QEMU_ARGS -device "$GFXDEV" -nographic -no-reboot
else
  exec "$QEMU" $QEMU_ARGS -nographic -no-reboot
fi
