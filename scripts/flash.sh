#!/bin/sh
# flash.sh — produce the flash image for real hardware and (optionally) write
# it via esptool. Writing happens ONLY when --port is given; the script never
# invents a port.
#
# Usage:   scripts/flash.sh [--soc esp32s3|esp32s31] [--port /dev/ttyUSB0]
#                           [--baud 460800] <prog.elf|prog.bin|prog.flash.img>
#
# The image written is mkflash.sh's --tight variant (content only), so only the
# real ~1 MB goes over the wire instead of the 16 MB QEMU padding. Baud
# defaults to 460800 (IDF's own default) and can be overridden with --baud or
# ESP_BAUD; esptool's built-in default is only 115200.
#
# Required environment: same as mkflash.sh (ESP32_SDK_PROJECT, and
# ESP_IDF_PATH or ESP_PYTHON_BIN).
set -e

soc=esp32s3
BAUD=${ESP_BAUD:-460800}
while :; do
  case "$1" in
    --soc)  soc="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --baud) BAUD="$2"; shift 2;;
    *) break;;
  esac
done

case "$soc" in
  esp32s3)  ESPTOOL_CHIP=esp32s3 ;;
  esp32s31) ESPTOOL_CHIP=esp32s31 ;;
  *) echo "unknown SoC: $soc (known: esp32s3 esp32s31)" >&2; exit 1;;
esac

[ $# -ge 1 ] || { echo "usage: $(basename $0) [--soc esp32s3|esp32s31] [--port /dev/ttyUSB0] [--baud 460800] <prog.elf|prog.bin|prog.flash.img>" >&2; exit 1; }
FILE=$1
case "$FILE" in /*) ;; *) FILE="$(pwd)/$FILE" ;; esac
[ -f "$FILE" ] || { echo "error: no such file: $FILE" >&2; exit 1; }

# --tight: content-only image (padded to the last merged piece, ~1 MB) instead
# of the full 16 MB flash-size image QEMU needs. Writing the padded image to
# hardware takes ~15x longer for no benefit — erased flash already reads 0xFF.
IMG=$("$(dirname -- "$0")/mkflash.sh" --soc "$soc" --tight "$FILE")

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

# Merged flash image is absolute from offset 0. Subcommand spelling follows
# the esptool major version, exactly like mkflash.sh: v4 uses write_flash,
# v5+ uses write-flash.
ESPT_VER=$(python -m esptool version 2>/dev/null | tail -1)
case "$ESPT_VER" in
  [5-9].*|[1-9][0-9].*) WRITE_CMD=write-flash ;;
  *)                     WRITE_CMD=write_flash ;;
esac
echo "writing $(wc -c < "$IMG" | tr -d ' ') bytes at $BAUD baud: $IMG"
python -m esptool --chip "$ESPTOOL_CHIP" --port "$PORT" --baud "$BAUD" "$WRITE_CMD" 0x0 "$IMG"
