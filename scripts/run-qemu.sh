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

# 3) boot configuration, from the same SDK project's sdkconfig
#    (see ../AGENTS.md §4 for env vars, §8 for the QEMU facts)
PRJ=${ESP32_SDK_PROJECT:-/mnt/storage/rewind-fpc-esp/blink-s3}
CFGH=$PRJ/build/config/sdkconfig.h

# SPIRAM sdkconfig ⇒ the mega-RAM boot: with the plain "-M <machine>
# -drive …,if=mtd" line the S3 bootloader reset-loops in its PSRAM init.
# Recipe mirrored from IDF's own idf.py qemu (tools/idf_py_actions/
# qemu_ext.py, verified end-to-end 2026-10-23): -m 32M, the efuse backing
# store + the nvram/timg -globals (efuse default = the chip-revision-0.3
# image idf.py qemu generates: 1 KiB, byte 38 = 0x0c), octal via -global
# on the machine-BUILTIN ssi_psram device (never -device a second one!).
if grep -aq '^#define CONFIG_SPIRAM 1' "$CFGH" 2>/dev/null; then
  [ -f "$PRJ/build/qemu_efuse.bin" ] || {
    python3 - "$PRJ/build/qemu_efuse.bin" <<'PYEOF' || exit 1
import sys
# byte-for-byte the image idf.py qemu generates (md5 ad7ad345bc3a2fb71a55c0d6a44fa612)
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

# graphics: enable an esp32* display device if this QEMU build has one
# (current espressif QEMU 9.2 esp32s3 machine: serial console only)
GFXDEV=$("$QEMU" -M "$QEMU_MACHINE" -device help 2>/dev/null \
         | grep -oE '"esp32[a-z0-9_-]*(lcd|display)[a-z0-9_-]*"' | head -1 | tr -d '"')
if [ -n "$GFXDEV" ]; then
  echo "--- booting with graphics device: $GFXDEV"
  exec "$QEMU" $QEMU_ARGS -device "$GFXDEV" -nographic -no-reboot
else
  exec "$QEMU" $QEMU_ARGS -nographic -no-reboot
fi
