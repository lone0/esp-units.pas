#!/bin/sh
# run-esp-emu.sh — boot a Pascal/IDF app in Espressif esp-emu (esp-emulator).
#
# Use this for SoCs QEMU cannot run yet. Default --soc is esp32s31.
# Serial console is on stdout. Test runners should wrap with `timeout`.
#
# Usage:   scripts/run-esp-emu.sh [--soc esp32s31] <prog.elf|prog.bin|prog.flash.img>
#
# Required environment:
#   ESP32_SDK_PROJECT  built ESP-IDF project (for mkflash.sh)
#   ESP_IDF_PATH or ESP_PYTHON_BIN  — for mkflash.sh / esptool
#   ESP_EMU            path to the esp-emu binary (or put esp-emu on PATH)
#
# Optional:
#   ESP_EMU_PSRAM      --psram-size value (default: 8M)
#   ESP_EMU_EXTRA      extra args appended to esp-emu
set -e

need_env() {
  eval "v=\${$1:-}"
  if [ -z "$v" ]; then
    echo "error: $1 is not set" >&2
    exit 1
  fi
}

soc=esp32s31
if [ "$1" = "--soc" ]; then
  [ $# -ge 2 ] || { echo "usage: $0 --soc <soc> <elf|bin|img>" >&2; exit 1; }
  soc="$2"; shift 2
fi

case "$soc" in
  esp32s31) CHIP=esp32s31 ;;
  *)
    echo "unknown/unsupported SoC for esp-emu here: $soc (known: esp32s31)" >&2
    echo "       for QEMU SoCs use: $(dirname -- "$0")/run-qemu.sh --soc <soc> ..." >&2
    exit 1
    ;;
esac

FILE=${1:?usage: $(basename $0) [--soc <soc>] <elf|bin|img>}
case "$FILE" in /*) ;; *) FILE="$(pwd)/$FILE" ;; esac
[ -f "$FILE" ] || { echo "error: no such file: $FILE" >&2; exit 1; }

need_env ESP32_SDK_PROJECT

IMG=$("$(dirname -- "$0")/mkflash.sh" --soc "$soc" "$FILE")

if [ -n "${ESP_EMU:-}" ]; then
  EMU=$ESP_EMU
else
  EMU=$(command -v esp-emu 2>/dev/null || true)
fi
[ -n "$EMU" ] && [ -x "$EMU" ] || {
  echo "error: esp-emu not found (set ESP_EMU or add esp-emu to PATH)" >&2
  exit 1
}

PSRAM=${ESP_EMU_PSRAM:-8M}

# shellcheck disable=SC2086
exec "$EMU" --chip "$CHIP" --firmware "$IMG" \
  --psram-size "$PSRAM" --exit-on _haltproc \
  ${ESP_EMU_EXTRA:-}
