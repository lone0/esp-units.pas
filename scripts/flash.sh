#!/bin/sh
# flash.sh — produce the flash image for real hardware and (optionally) write
# it via esptool. Writing happens ONLY when --port is given; the script never
# invents a port. What is written is byte-identical to the QEMU boot image.
#
# Usage:   scripts/flash.sh [--soc esp32s3|esp32c3] [--port /dev/ttyUSB0] <prog.elf|prog.bin|prog.flash.img>
# Out:     without --port: prints the image path and exits (idempotent, safe;
#          the file also serves as the "flash upload" artifact name).
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
  esp32c3)  ESPTOOL_CHIP=esp32c3 ;;
  *) echo "unknown SoC: $soc (known: esp32s3 esp32c3)" >&2; exit 1;;
esac

FILE=${1:?usage: $(basename $0) [--soc <soc>] [--port /dev/ttyX] <elf|bin|img>}
case "$FILE" in /*) ;; *) FILE="$(pwd)/$FILE" ;; esac
[ -f "$FILE" ] || { echo "error: no such file: $FILE" >&2; exit 1; }

IMG=$("$(dirname -- "$0")/mkflash.sh" --soc "$soc" "$FILE")

if [ -z "$PORT" ]; then
  echo "no --port given; image ready for esptool (not written): $IMG"
  exit 0
fi

export IDF_PATH=${ESP_IDF_PATH:-/mnt/storage/rewind-fpc-esp/esp-idf-v5.2.8}
IDF_MM=$(basename "$IDF_PATH" | sed -n 's/^esp-idf-v\([0-9]*\.[0-9]*\).*$/\1/p')
export PATH="${ESP_PYTHON_BIN:-$(ls -d "$HOME"/.espressif/python_env/idf${IDF_MM:-5.2}_*/bin 2>/dev/null | head -1)}:$PATH"
python -m esptool --chip "$ESPTOOL_CHIP" --port "$PORT" write_flash 0x0 "$IMG"
