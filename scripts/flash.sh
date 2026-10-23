#!/bin/sh
# flash.sh — produce the flash image for real hardware and (optionally) write
# it via esptool. Writing happens ONLY when --port is given; the script never
# invents a port.
#
# Usage:   scripts/flash.sh [--soc esp32s3|esp32s31] [--port /dev/ttyUSB0] <prog.elf|prog.bin|prog.flash.img>
#
# Required environment: same as mkflash.sh (ESP32_SDK_PROJECT, and
# ESP_IDF_PATH or ESP_PYTHON_BIN).
set -e

soc=esp32s3
while :; do
  case "$1" in
    --soc)  soc="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    *) break;;
  esac
done

case "$soc" in
  esp32s3)  ESPTOOL_CHIP=esp32s3 ;;
  esp32s31) ESPTOOL_CHIP=esp32s31 ;;
  *) echo "unknown SoC: $soc (known: esp32s3 esp32s31)" >&2; exit 1;;
esac

FILE=${1:?usage: $(basename $0) [--soc <soc>] [--port /dev/ttyX] <elf|bin|img>}
case "$FILE" in /*) ;; *) FILE="$(pwd)/$FILE" ;; esac
[ -f "$FILE" ] || { echo "error: no such file: $FILE" >&2; exit 1; }

IMG=$("$(dirname -- "$0")/mkflash.sh" --soc "$soc" "$FILE")

if [ -z "$PORT" ]; then
  echo "no --port given; image ready for esptool (not written): $IMG"
  exit 0
fi

# mkflash.sh already put a working esptool on PATH when it ran in this shell
# tree; re-resolve for the write step the same way.
if [ -n "${ESP_PYTHON_BIN:-}" ]; then
  export PATH="$ESP_PYTHON_BIN:$PATH"
elif [ -n "${ESP_IDF_PATH:-}" ]; then
  export IDF_PATH=$ESP_IDF_PATH
  IDF_MM=$(basename "$IDF_PATH" | sed -n 's/^esp-idf-v\([0-9]*\.[0-9]*\).*$/\1/p')
  PYBIN=
  if [ -n "$IDF_MM" ]; then
    PYBIN=$(ls -d "$HOME"/.espressif/python_env/idf${IDF_MM}_*/bin 2>/dev/null | head -1)
  fi
  [ -d "$PYBIN" ] || { echo "error: idf python venv not found (set ESP_PYTHON_BIN)" >&2; exit 1; }
  export PATH="$PYBIN:$PATH"
else
  echo "error: set ESP_PYTHON_BIN or ESP_IDF_PATH for esptool" >&2
  exit 1
fi

# Merged flash image is absolute from offset 0.
python -m esptool --chip "$ESPTOOL_CHIP" --port "$PORT" write-flash 0x0 "$IMG"
