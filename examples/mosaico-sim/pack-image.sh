#!/bin/sh
# Re-pack mosaico_sim.elf with 64KB MMU pages (bootloader alignment).
set -e
cd "$(dirname "$0")"
esptool --chip esp32s31 elf2image \
  --flash-mode qio --flash-freq 80m --flash-size 16MB \
  --flash-mmu-page-size 64KB \
  -o mosaico_sim.bin mosaico_sim.elf
