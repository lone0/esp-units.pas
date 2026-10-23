#!/bin/sh
# mkflash.sh — produce the flashable ESP image for a Pascal app.
#
# Usage:   scripts/mkflash.sh [--soc esp32s3|esp32c3] <prog.elf|prog.bin|flash-image.img>
# Output:  <prog>.flash.img next to the source (application .elf inputs are
#          converted + merged through esptool exactly like FPC's linker does).
#
# The image layout is fixed:   0x0 bootloader | 0x8000 partition table | 0x10000 app
# (bootloader/table come from an ALREADY-INSTALLED external ESP-IDF project
# whose build dir provides them - see EPS32_SDK_PROJECT in ../README.md).
set -e
soc=esp32s3
if [ "$1" = "--soc" ]; then
  [ $# -ge 2 ] || { echo "usage: $0 --soc <soc> <elf|bin|img>" >&2; exit 1; }
  soc="$2"; shift 2
fi

case "$soc" in
  esp32s3)  ESPTOOL_CHIP=esp32s3 ;;
  esp32c3)  ESPTOOL_CHIP=esp32c3 ;;
  *) echo "unknown SoC: $soc (known: esp32s3 esp32c3)" >&2; exit 1;;
esac

FILE=${1:?usage: $(basename $0) [--soc <soc>] <elf|bin|img>}
case "$FILE" in /*) ;; *) FILE="$(pwd)/$FILE" ;; esac
[ -f "$FILE" ] || { echo "error: no such file: $FILE" >&2; exit 1; }

# bootloader + partition table + sdkconfig come from the external IDF project
PRJ=${ESP32_SDK_PROJECT:-/mnt/storage/rewind-fpc-esp/blink-s3}
B=$PRJ/build
BL=$B/bootloader/bootloader.bin
PT=$B/partition_table/partition-table.bin
[ -f "$BL" ] && [ -f "$PT" ] || {
  echo "error: IDF project $PRJ has no built bootloader/partition table." >&2
  echo "       do the one-time 'idf.py build' in it (or set ESP32_SDK_PROJECT)" >&2
  exit 1
}
FLASH=$(awk '/CONFIG_ESPTOOLPY_FLASHSIZE "/{gsub(/"/,"",$3);print $3}' "$B/config/sdkconfig.h" 2>/dev/null)
FLASH=${FLASH:-2MB}

export IDF_PATH=${ESP_IDF_PATH:-/mnt/storage/rewind-fpc-esp/esp-idf-v5.2.8}
# match the IDF python venv to IDF_PATH's version (esptool must import)
IDF_MM=$(basename "$IDF_PATH" | sed -n 's/^esp-idf-v\([0-9]*\.[0-9]*\).*$/\1/p')
export PATH="${ESP_PYTHON_BIN:-$(ls -d "$HOME"/.espressif/python_env/idf${IDF_MM:-5.2}_*/bin 2>/dev/null | head -1)}:$PATH"

IMG="${FILE%.*}.flash.img"
APP=$FILE
case "$FILE" in
  *.elf)
    # ESP app image from ELF - the same flags FPC's linker (t_freertos.pas) uses
    python -m esptool --chip "$ESPTOOL_CHIP" elf2image --flash_size "$FLASH" \
      --elf-sha256-offset 0xb0 -o "$IMG.app" "$FILE" > /dev/null
    APP="$IMG.app"
    ;;
  *.img|*.factory*)
    # complete flash image handed in directly - normalize size and stop
    cp "$FILE" "$IMG"
    QEMU_IMG=1
    ;;
esac

if [ -z "$QEMU_IMG" ]; then
  python -m esptool --chip "$ESPTOOL_CHIP" merge_bin -o "$IMG" --flash_mode dio \
    --flash_size "$FLASH" --flash_freq 80m \
    0x0 "$BL" 0x8000 "$PT" 0x10000 "$APP" > /dev/null
  [ "$APP" != "$FILE" ] && rm -f "$IMG.app"
fi
truncate -s "${FLASH%MB}M" "$IMG"
echo "$IMG"
