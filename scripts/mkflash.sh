#!/bin/sh
# mkflash.sh — produce the flashable ESP image for a Pascal app.
#
# Usage:   scripts/mkflash.sh [--soc esp32s3|esp32s31] <prog.elf|prog.bin|flash-image.img>
# Output:  <prog>.flash.img next to the source.
#
# Layout (offsets from the SDK project's sdkconfig when present):
#   bootloader | partition table | 0x10000 app
# Fallback bootloader offsets when sdkconfig omits them: S3 0x0, S31 0x2000; PT 0x8000.
#
# Required environment:
#   ESP32_SDK_PROJECT  built ESP-IDF project (bootloader + partition table)
#   ESP_IDF_PATH       ESP-IDF root (for esptool via its python env), unless
#                      ESP_PYTHON_BIN already provides a working esptool
#
# Optional:
#   ESP_PYTHON_BIN     python venv bin/ that can import esptool
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
  esp32s3)  ESPTOOL_CHIP=esp32s3; BL_DEFAULT=0x0 ;;
  esp32s31) ESPTOOL_CHIP=esp32s31; BL_DEFAULT=0x2000 ;;
  *) echo "unknown SoC: $soc (known: esp32s3 esp32s31)" >&2; exit 1;;
esac

FILE=${1:?usage: $(basename $0) [--soc <soc>] <elf|bin|img>}
case "$FILE" in /*) ;; *) FILE="$(pwd)/$FILE" ;; esac
[ -f "$FILE" ] || { echo "error: no such file: $FILE" >&2; exit 1; }

need_env ESP32_SDK_PROJECT
PRJ=$ESP32_SDK_PROJECT
B=$PRJ/build
BL=$B/bootloader/bootloader.bin
PT=$B/partition_table/partition-table.bin
[ -f "$BL" ] && [ -f "$PT" ] || {
  echo "error: IDF project $PRJ has no built bootloader/partition table." >&2
  echo "       run idf.py build there, or point ESP32_SDK_PROJECT at a built tree" >&2
  exit 1
}
FLASH=$(awk '/CONFIG_ESPTOOLPY_FLASHSIZE "/{gsub(/"/,"",$3);print $3}' "$B/config/sdkconfig.h" 2>/dev/null)
FLASH=${FLASH:-2MB}

CFG=
if [ -f "$PRJ/sdkconfig" ]; then
  CFG=$PRJ/sdkconfig
elif [ -f "$B/config/sdkconfig.h" ]; then
  CFG=$B/config/sdkconfig.h
fi
BL_OFF=$BL_DEFAULT
PT_OFF=0x8000
if [ -n "$CFG" ]; then
  v=$(sed -n 's/^CONFIG_BOOTLOADER_OFFSET_IN_FLASH=//p' "$CFG" | head -1)
  [ -n "$v" ] && BL_OFF=$v
  v=$(sed -n 's/^CONFIG_PARTITION_TABLE_OFFSET=//p' "$CFG" | head -1)
  [ -n "$v" ] && PT_OFF=$v
  if [ "$BL_OFF" = "$BL_DEFAULT" ]; then
    v=$(sed -n 's/^#define CONFIG_BOOTLOADER_OFFSET_IN_FLASH //p' "$CFG" | head -1)
    [ -n "$v" ] && BL_OFF=$v
  fi
  if [ "$PT_OFF" = "0x8000" ]; then
    v=$(sed -n 's/^#define CONFIG_PARTITION_TABLE_OFFSET //p' "$CFG" | head -1)
    [ -n "$v" ] && PT_OFF=$v
  fi
fi

if [ -n "${ESP_PYTHON_BIN:-}" ]; then
  export PATH="$ESP_PYTHON_BIN:$PATH"
else
  need_env ESP_IDF_PATH
  export IDF_PATH=$ESP_IDF_PATH
  IDF_MM=$(basename "$IDF_PATH" | sed -n 's/^esp-idf-v\([0-9]*\.[0-9]*\).*$/\1/p')
  PYBIN=
  if [ -n "$IDF_MM" ]; then
    PYBIN=$(ls -d "$HOME"/.espressif/python_env/idf${IDF_MM}_*/bin 2>/dev/null | head -1)
  fi
  [ -d "$PYBIN" ] || { echo "error: idf python venv not found (set ESP_PYTHON_BIN)" >&2; exit 1; }
  export PATH="$PYBIN:$PATH"
fi

IMG="${FILE%.*}.flash.img"
APP=$FILE
case "$FILE" in
  *.elf)
    python -m esptool --chip "$ESPTOOL_CHIP" elf2image --flash-size "$FLASH" \
      --elf-sha256-offset 0xb0 -o "$IMG.app" "$FILE" > /dev/null
    APP="$IMG.app"
    ;;
  *.img|*.factory*)
    cp "$FILE" "$IMG"
    QEMU_IMG=1
    ;;
esac

if [ -z "$QEMU_IMG" ]; then
  python -m esptool --chip "$ESPTOOL_CHIP" merge-bin -o "$IMG" --flash-mode dio \
    --flash-size "$FLASH" --flash-freq 80m \
    "$BL_OFF" "$BL" "$PT_OFF" "$PT" 0x10000 "$APP" > /dev/null
  [ "$APP" != "$FILE" ] && rm -f "$IMG.app"
fi
truncate -s "${FLASH%MB}M" "$IMG"
echo "$IMG"
