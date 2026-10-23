#!/bin/sh
# run-qemu.sh — boot a Pascal/IDF app in the Espressif QEMU, serial console
# on stdout, until the emulator exits (-no-reboot). Test runners cap the
# wall-clock with `timeout`.
#
# Usage:   scripts/run-qemu.sh [--soc esp32s3|esp32c3] <prog.elf|prog.bin|prog.flash.img>
#          (an .elf/.bin is converted to a flash image first via mkflash.sh;
#           the prerequisites of mkflash.sh therefore apply here too)
set -e
soc=esp32s3
if [ "$1" = "--soc" ]; then
  [ $# -ge 2 ] || { echo "usage: $0 --soc <soc> <elf|bin|img>" >&2; exit 1; }
  soc="$2"; shift 2
fi

case "$soc" in
  esp32s3)  QEMU_MACHINE=esp32s3 ;;
  esp32c3)  QEMU_MACHINE=esp32c3 ;;
  *) echo "unknown SoC: $soc (known: esp32s3 esp32c3)" >&2; exit 1;;
esac

FILE=${1:?usage: $(basename $0) [--soc <soc>] <elf|bin|img>}
case "$FILE" in /*) ;; *) FILE="$(pwd)/$FILE" ;; esac
[ -f "$FILE" ] || { echo "error: no such file: $FILE" >&2; exit 1; }

# 1) flash image (elf -> app image -> merged image; bare .img passes through)
IMG=$("$(dirname -- "$0")/mkflash.sh" --soc "$soc" "$FILE")

# 2) emulator
QEMU=$(find "$HOME"/.espressif/tools -name qemu-system-xtensa -type f 2>/dev/null | head -1)
[ -n "$QEMU" ] || { echo "error: qemu-system-xtensa not found under ~/.espressif/tools" >&2; exit 1; }

# graphics: enable an esp32* display device if this QEMU build has one
# (current espressif QEMU 9.2 esp32s3 machine: serial console only)
GFXDEV=$("$QEMU" -M "$QEMU_MACHINE" -device help 2>/dev/null \
         | grep -oE '"esp32[a-z0-9_-]*(lcd|display)[a-z0-9_-]*"' | head -1 | tr -d '"')
if [ -n "$GFXDEV" ]; then
  echo "--- booting with graphics device: $GFXDEV"
  exec "$QEMU" -M "$QEMU_MACHINE" -device "$GFXDEV" \
    -drive file="$IMG",if=mtd,format=raw -no-reboot
else
  exec "$QEMU" -M "$QEMU_MACHINE" -nographic \
    -drive file="$IMG",if=mtd,format=raw -no-reboot
fi
