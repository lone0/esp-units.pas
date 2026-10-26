#!/bin/sh
# build.sh — cross-build a Pascal program for an ESP32-family SoC.
#
# INVARIANT (see ../AGENTS.md): fpc and esp-idf are EXTERNAL tools to this
# repo. This script never guesses where they live — set the env vars below.
#
# Usage:   scripts/build.sh [--soc esp32s3|esp32s31] [fpc options] <prog.pas>
#          scripts/build.sh prog.pas                 # default SoC: esp32s3
# Output:  prog.o / prog.elf / prog.bin / prog.img written next to the source.
#
# Required environment:
#   ESP_FPC_ROOT       fpc-cross install for *this* build — tree with
#                      lib/fpc/<ver>/ppcross{xtensa|riscv32} and lib/fpc/etc/fpc.cfg.
#                      Point it at the xtensa tree for esp32s3, the riscv32 tree
#                      for esp32s31 (or any future SoC). --soc only selects the
#                      binary name + MCU flags inside that root.
#   ESP_IDF_VERSION    IDF version string for -WP (e.g. 6.1)
#   ESP32_SDK_PROJECT  built ESP-IDF project (bootloader, sdkconfig, libesp_psram.a)
#
# Optional (else discovered from the toolchain fpc.cfg -Fl lines / IDF_PATH):
#   ESP_IDF_PATH       ESP-IDF root (esptool.py)
#   ESP_TOOLCHAIN_BIN  <xtensa|riscv32>-esp-elf/bin
#   ESP_PYTHON_BIN     python venv bin/ that can import esptool
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

usage() {
  cat <<'EOF'
usage: scripts/build.sh [--soc esp32s3|esp32s31] [fpc options] <prog.pas>

Cross-build a Pascal program for an ESP32-family SoC.

Required environment (this script never guesses host paths):
  ESP_FPC_ROOT       fpc-cross install for THIS build.
                       esp32s3  -> the tree holding lib/fpc/<ver>/ppcrossxtensa
                       esp32s31 -> the tree holding lib/fpc/<ver>/ppcrossriscv32
                     e.g.  ESP_FPC_ROOT=$HOME/fpc-cross/fpc-xtensa
  ESP_IDF_VERSION    version string passed as -WP; selects the espidf_<NNN> unit
                     e.g.  ESP_IDF_VERSION=6.1
  ESP32_SDK_PROJECT  a built ESP-IDF project (idf.py build already run):
                     build/bootloader/bootloader.bin, build/partition_table/,
                     build/config/sdkconfig.h (+ build/esp-idf/esp_psram/ when
                     CONFIG_SPIRAM is on)
                     e.g.  ESP32_SDK_PROJECT=$HOME/esp/my-idf-project
                     It must also build every component the freertos RTL
                     binding link-lists, because an unbuilt component leaves
                     no archive to link (add them to the app's REQUIRES):
                       esp_phy esp_coex driver vfs mbedtls esp_driver_uart
                       esp_driver_usb_serial_jtag   [+ esp_psram, esp_ringbuf]

Optional (default: discovered from the toolchain's own fpc.cfg -Fl lines,
else from the SDK project's build/project_description.json):
  ESP_IDF_PATH       ESP-IDF root providing esptool.py
                     e.g.  ESP_IDF_PATH=$HOME/esp/esp-idf
  ESP_TOOLCHAIN_BIN  <xtensa|riscv32>-esp-elf/bin (compiler shells as/ld out)
                     e.g.  ESP_TOOLCHAIN_BIN=$HOME/.espressif/tools/
                             xtensa-esp-elf/<toolchain-ver>/xtensa-esp-elf/bin
  ESP_PYTHON_BIN     python venv bin/ that can import esptool
                     e.g.  ESP_PYTHON_BIN=$HOME/.espressif/python_env/
                             idf6.1_py3.14_env/bin

Derived automatically (no hand-edited fpc.cfg needed):
  binutils prefix   <- *-<chip>-*gcc in the binutils dir (passed as -XP)
  binutils dir +    <- the SDK project's build/project_description.json
  IDF root             ("c_compiler" / "idf_path") when neither the env nor
                       the toolchain fpc.cfg supplies them
  FPU mode          <- ppudump on the installed RTL's system.ppu, passed as
                       -Cfsoft/-Cfhard so it always matches the units; the
                       package units are probed too, and a half-reinstalled
                       toolchain (RTL rebuilt, packages stale) is reported as
                       such instead of failing later with "Can't find unit"
  link closure      <- -Fl for the SDK project's build/esp-idf/** (recursive:
                       some components keep archives below the top level, e.g.
                       mbedtls/mbedtls/library/libmbedcrypto.a), IDF's per-chip
                       ld scripts + prebuilt libs, and the toolchain's
                       libgcc/sysroot for the chip. A fpc.cfg that already has
                       these is fine; duplicates are harmless.
  libc scheme       <- when the project built esp_libc (IDF 6.x), the
                       toolchain's picolibc lib/<chip> is searched before the
                       legacy newlib dir; esp_libc needs picolibc's __bufio_*

Options:
  --soc esp32s3      xtensa lx7 (default): ppcrossxtensa, -WpESP32S3
  --soc esp32s31     riscv32: ppcrossriscv32, -WpESP32S31
  [fpc options]      forwarded to the compiler; later options win
                     (e.g. -Ch1024 overrides a -Ch from fpc.cfg)
  --help             show this help

Examples:
  export ESP_FPC_ROOT=... ESP_IDF_VERSION=6.1 ESP32_SDK_PROJECT=...
  scripts/build.sh examples/idfheap-smoke.pas

  # switch SoC: point ESP_FPC_ROOT (and the SDK project) at the riscv32 pair
  ESP_FPC_ROOT=... ESP32_SDK_PROJECT=... \
    scripts/build.sh --soc esp32s31 examples/idfheap-smoke.pas
EOF
}

[ "${1:-}" = "--help" ] && { usage; exit 0; }

need_env() {
  eval "v=\${$1:-}"
  if [ -z "$v" ]; then
    echo "error: $1 is not set" >&2
    exit 1
  fi
}

find_ppc() {
  # $1 = FPC_ROOT, $2 = binary name (ppcrossxtensa | ppcrossriscv32)
  root=$1
  name=$2
  found=
  for cand in "$root"/lib/fpc/*/"$name"; do
    if [ -x "$cand" ]; then
      if [ -n "$found" ]; then
        echo "error: multiple $name under $root/lib/fpc (set a single-version install)" >&2
        exit 1
      fi
      found=$cand
    fi
  done
  if [ -z "$found" ]; then
    echo "error: $name not found under $root/lib/fpc/*/ — is ESP_FPC_ROOT the right install for --soc?" >&2
    exit 1
  fi
  printf '%s\n' "$found"
}

soc=esp32s3
if [ "$1" = "--soc" ]; then
  [ $# -ge 2 ] || { echo "usage: $0 --soc <name> ..." >&2; exit 1; }
  soc="$2"; shift 2
fi

[ $# -ge 1 ] || {
  echo "usage: $(basename "$0") [--soc <name>] [fpc options] <prog.pas>" >&2
  echo "       run $(basename "$0") --help for the required environment" >&2
  exit 1
}

need_env ESP_FPC_ROOT
need_env ESP_IDF_VERSION
need_env ESP32_SDK_PROJECT
FPC_ROOT=$ESP_FPC_ROOT
IDF_VER=$ESP_IDF_VERSION
PRJ=$ESP32_SDK_PROJECT

# --- per-SoC table: MCU / compiler binary / binutils family only ------------
case "$soc" in
  esp32s3)
    PPC_NAME=ppcrossxtensa
    MCU=-WpESP32S3
    ESPTOOL_CHIP=esp32s3
    TOOLCHAIN_NAME=xtensa-esp-elf
    ;;
  esp32s31)
    PPC_NAME=ppcrossriscv32
    MCU=-WpESP32S31
    ESPTOOL_CHIP=esp32s31
    TOOLCHAIN_NAME=riscv32-esp-elf
    ;;
  *)
    echo "unknown SoC: $soc (known: esp32s3 esp32s31)" >&2; exit 1;;
esac

PPC=$(find_ppc "$FPC_ROOT" "$PPC_NAME")
[ -x "$PPC" ] || { echo "cross compiler missing: $PPC" >&2; exit 1; }

# Discover binutils + IDF root from the toolchain's own fpc.cfg -Fl lines
# (env overrides win). No host path defaults.
CFG=$FPC_ROOT/lib/fpc/etc/fpc.cfg
[ -f "$CFG" ] || { echo "error: missing $CFG" >&2; exit 1; }
TC_MATCH=$(sed -n "s|^ *-Fl\\(.*/$TOOLCHAIN_NAME/[^/]*\\)/$TOOLCHAIN_NAME/.*|\\1|p" "$CFG" 2>/dev/null | head -1)
TC_BIN=
if [ -n "${ESP_TOOLCHAIN_BIN:-}" ]; then
  TC_BIN=$ESP_TOOLCHAIN_BIN
elif [ -n "$TC_MATCH" ]; then
  TC_BIN=$TC_MATCH/$TOOLCHAIN_NAME/bin
fi

# Second fallback source for binutils + IDF root: the SDK project's own build
# description. idf.py records the compiler it used ("c_compiler") and the IDF
# tree it was built from ("idf_path"), so a plain install + built project is
# enough — no cfg editing, no extra env.
PRJ_DESC=$PRJ/build/project_description.json
json_val() {
  [ -f "$PRJ_DESC" ] || return 0
  sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PRJ_DESC" 2>/dev/null | head -1
}
if [ -z "$TC_BIN" ]; then
  _cc=$(json_val c_compiler)
  [ -n "$_cc" ] && TC_BIN=$(dirname -- "$_cc")
fi
if [ -n "${ESP_IDF_PATH:-}" ]; then
  IDF_PATH=$ESP_IDF_PATH
else
  IDF_PATH=$(sed -n 's|^ *-Fl\(/.*/esp-idf[^/]*\)/.*|\1|p' "$CFG" 2>/dev/null | head -1)
  [ -n "$IDF_PATH" ] || IDF_PATH=$(json_val idf_path)
fi
[ -d "$TC_BIN" ] || {
  echo "esp binutils not found. Set ESP_TOOLCHAIN_BIN, or use a toolchain whose" >&2
  echo "  fpc.cfg has -Fl …/$TOOLCHAIN_NAME/…, or a built SDK project whose" >&2
  echo "  build/project_description.json names the compiler ($PRJ_DESC)." >&2
  exit 1
}
[ -d "$IDF_PATH" ] || {
  echo "ESP-IDF root not found. Set ESP_IDF_PATH, or use a toolchain whose" >&2
  echo "  fpc.cfg has -Fl …/esp-idf…, or an SDK project built from an IDF tree." >&2
  exit 1
}
export PATH="$TC_BIN:$PATH" IDF_PATH

# --- link closure, derived (no hand-edited fpc.cfg required) ----------------
# A plain `make install` fpc.cfg carries no IDF -Fl lines; the linker then
# fails on memory.ld, libesp_*.a or the toolchain's libgcc. Everything needed
# is derivable from the three locations we already have: the SDK project, the
# IDF root and the binutils dir. Directories are added only when they really
# hold archives/linker scripts, so this works for any IDF version.
# (Paths must not contain spaces — same assumption the fpc.cfg approach makes.)
TC_ROOT=$(CDPATH= cd -- "$TC_BIN/.." && pwd)
FL_OPTS=
has_libs() {
  for _f in "$1"/*.a "$1"/*.ld; do
    [ -e "$_f" ] && return 0
  done
  return 1
}
add_fl() {
  [ -d "$1" ] || return 0
  has_libs "$1" || return 0
  case " $FL_OPTS " in *" -Fl$1 "*) return 0;; esac
  FL_OPTS="$FL_OPTS -Fl$1"
}
# 1) linker scripts: from the SDK build, then the ones IDF ships per chip
for d in "$PRJ"/build/esp-idf/*/ld "$IDF_PATH"/components/*/"$ESPTOOL_CHIP"/ld; do
  add_fl "$d"
done
# 2) prebuilt archives inside IDF (wifi/phy/coex/openthread/…) + chip support
for d in "$IDF_PATH"/components/*/lib/"$ESPTOOL_CHIP" "$IDF_PATH"/components/*/"$ESPTOOL_CHIP"; do
  add_fl "$d"
done
# 3) every component archive the SDK project built. Recursive on purpose:
#    some components keep their archives below the top level (e.g.
#    build/esp-idf/mbedtls/mbedtls/library/libmbedcrypto.a).
if [ -d "$PRJ/build/esp-idf" ]; then
  for d in $(find "$PRJ/build/esp-idf" -maxdepth 6 -type d 2>/dev/null | sort); do
    add_fl "$d"
  done
fi
# 4) toolchain runtime: libgcc and the chip's sysroot lib dir
for d in "$TC_ROOT"/*/lib/"$ESPTOOL_CHIP" "$TC_ROOT"/lib/gcc/*/*/"$ESPTOOL_CHIP"; do
  add_fl "$d"
done

# 5) libc scheme. IDF 6.x builds its own esp_libc on top of the toolchain's
#    *picolibc*, while the same toolchain still ships a legacy newlib
#    libc.a in xtensa-esp-elf/lib/<chip>. Both define printf/malloc, so the
#    link order decides: esp_libc's startup object references picolibc's
#    __bufio_* helpers, which only picolibc's libc.a provides. When the SDK
#    project built esp_libc, that dir therefore has to come first.
if [ -d "$PRJ/build/esp-idf/esp_libc" ]; then
  for d in "$TC_ROOT"/picolibc/*/lib/"$ESPTOOL_CHIP"; do
    [ -d "$d" ] || continue
    has_libs "$d" || continue
    case " $FL_OPTS " in *" -Fl$d "*) continue;; esac
    FL_OPTS="-Fl$d $FL_OPTS"
  done
fi

# Cross binutils prefix (<prefix>gcc in the binutils dir), so a bare install
# whose fpc.cfg still says -XP$FPCTARGET- (-> "xtensa-freertos-as") works.
BIN_PREFIX=
for c in "$TC_BIN"/*-"$ESPTOOL_CHIP"-*gcc; do
  [ -x "$c" ] && { BIN_PREFIX=$(basename "$c" gcc); break; }
done
[ -n "$BIN_PREFIX" ] || {
  echo "error: ESP_TOOLCHAIN_BIN has no *-$ESPTOOL_CHIP-*-gcc; it does not match --soc $soc" >&2
  exit 1
}

# FPU mode must match the installed RTL, and a plain fpc.cfg says nothing
# about it (the compiler's built-in default may differ from how the RTL was
# built -> "Trying to use a unit which was compiled with a different FPU
# mode"). Ask the RTL itself via ppudump when that tool is available.
FPU_OPT=
TARGET_UNITS=
for u in "$FPC_ROOT"/lib/fpc/*/units/"${PPC_NAME#ppcross}"-freertos/rtl/system.ppu; do
  [ -f "$u" ] && { TARGET_UNITS=$u; break; }
done
PPUDUMP=$(ls "$FPC_ROOT"/bin/ppudump "$FPC_ROOT"/lib/fpc/*/ppudump 2>/dev/null | head -1)
[ -n "$PPUDUMP" ] || PPUDUMP=$(command -v ppudump 2>/dev/null || true)
if [ -n "$PPUDUMP" ] && [ -x "$PPUDUMP" ] && [ -f "$TARGET_UNITS" ]; then
  if "$PPUDUMP" "$TARGET_UNITS" 2>/dev/null | grep -q 'Unit flags.*fpu_emulation_on'; then
    FPU_OPT=-Cfsoft
  elif "$PPUDUMP" "$TARGET_UNITS" 2>/dev/null | grep -q 'Unit flags'; then
    FPU_OPT=-Cfhard
  fi
fi

# A partially reinstalled toolchain (e.g. `make install` for the RTL only)
# leaves package units built with the *other* FPU mode. They still exist, so
# the compiler reports a baffling "Can't find unit Generics.Collections" --
# say what is really wrong instead.
if [ -n "$FPU_OPT" ] && [ -n "$TARGET_UNITS" ]; then
  UNITS_DIR=$(dirname -- "$TARGET_UNITS")/..
  for p in "$UNITS_DIR"/rtl-generics/generics.collections.ppu \
           "$UNITS_DIR"/rtl-objpas/variants.ppu; do
    [ -f "$p" ] || continue
    _pf=$("$PPUDUMP" "$p" 2>/dev/null | grep -m1 'Unit flags')
    [ -n "$_pf" ] || continue
    _mismatch=
    if [ "$FPU_OPT" = -Cfsoft ]; then
      case "$_pf" in *fpu_emulation_on) ;; *) _mismatch=1;; esac
    else
      case "$_pf" in *fpu_emulation_on) _mismatch=1;; esac
    fi
    [ -n "$_mismatch" ] && {
      echo "warning: installed FPC units are inconsistent: $(basename "$TARGET_UNITS") is" >&2
      echo "  ${FPU_OPT#-Cf}-float but ${p#$UNITS_DIR/} was built with the other FPU mode." >&2
      echo "  Units using it will look missing. Reinstall the whole toolchain with one" >&2
      echo "  flag set (make all install, i.e. RTL *and* packages)." >&2
      break
    }
  done
fi

# esptool must be importable by the python the compiler invokes.
if [ -n "${ESP_PYTHON_BIN:-}" ]; then
  PYBIN=$ESP_PYTHON_BIN
else
  IDF_MAJOR_MINOR=$(basename "$IDF_PATH" | sed -n 's/^esp-idf-v\([0-9]*\.[0-9]*\).*$/\1/p')
  if [ -n "$IDF_MAJOR_MINOR" ]; then
    PYBIN=$(ls -d "$HOME"/.espressif/python_env/idf${IDF_MAJOR_MINOR}_*/bin 2>/dev/null | head -1)
  else
    PYBIN=
  fi
fi
[ -d "$PYBIN" ] || { echo "idf python venv not found (set ESP_PYTHON_BIN)" >&2; exit 1; }
export PATH="$PYBIN:$PATH"

# --- SPIRAM link closure ----------------------------------------------------
# When the SDK project was built WITH CONFIG_SPIRAM, its esp_system/freertos
# archives gain references to esp_psram_* symbols (libesp_psram.a). FPC only
# injects an extra archive when a USED unit carries {$linklib <n>,static}.
# idfheap carries {$linklib esp_psram,static} under -dESPSDK_SPIRAM.
CFGH=$PRJ/build/config/sdkconfig.h
if grep -aq '^#define CONFIG_SPIRAM 1' "$CFGH" 2>/dev/null; then
  PSRAM_LIBDIR=$PRJ/build/esp-idf/esp_psram
  [ -f "$PSRAM_LIBDIR/libesp_psram.a" ] || {
    echo "SPIRAM sdkconfig detected in $CFGH but $PSRAM_LIBDIR/libesp_psram.a is missing - rebuild the SDK project first" >&2
    exit 1
  }
  STAMP=$REPO/units/.idfheap-spiram-state-$soc
  if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$PSRAM_LIBDIR" ]; then
    rm -f "$REPO/units/idfheap.ppu" "$REPO/units/idfheap.o"
    printf '%s\n' "$PSRAM_LIBDIR" > "$STAMP"
  fi
  set -- -dESPSDK_SPIRAM "-Fl$PSRAM_LIBDIR" "$@"
fi

# -Tfreertos + -Wp<MCU> + -WP<IDF ver>; units/ via -Fu. Later options win, so
# user-supplied options still override -XP/dirs. $FL_OPTS is deliberately
# unquoted: it is a space-separated list of -Fl options built above.
exec "$PPC" -Tfreertos "$MCU" "-WP$IDF_VER" "-XP$BIN_PREFIX" $FPU_OPT \
  "-Fu$REPO/units" "-Fu$REPO/units/espatomics" $FL_OPTS "$@"
