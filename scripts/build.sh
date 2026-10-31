#!/bin/sh
# build.sh — cross-build a Pascal program for an ESP32-family SoC.
#
# INVARIANT (see ../AGENTS.md): fpc and esp-idf are EXTERNAL tools to this
# repo. This script never guesses where they live — set the env vars below.
#
# Usage:   scripts/build.sh [--soc esp32s3|esp32s31] [--c src.c …] [fpc options]
#                           <prog.pas>
#          scripts/build.sh prog.pas                 # default SoC: esp32s3
# Output:  prog.o / prog.elf / prog.bin / prog.img written next to the source.
#
# Required environment:
#   ESP_FPC_ROOT       fpc-cross install for *this* build — tree with
#                      lib/fpc/<ver>/ppcrossxtensa and/or ppcrossrv32
#                      (fpc.cfg optional). Point it at the tree holding the
#                      compiler --soc needs (or any future SoC). --soc only
#                      selects the binary name + MCU flags inside that root.
#   ESP_IDF_VERSION    IDF version string for -WP (default: 6.1)
#   ESP32_SDK_PROJECT  built ESP-IDF project (bootloader, sdkconfig; the
#                      script links libesp_psram.a / libespcoredump.a from it
#                      when the project provides them)
#
# Optional (else discovered from the toolchain fpc.cfg -Fl lines / IDF_PATH):
#   ESP_IDF_PATH       ESP-IDF root (esptool.py)
#   ESP_TOOLCHAIN_BIN  <xtensa|riscv32>-esp-elf/bin
#   ESP_PYTHON_BIN     python venv bin/ that can import esptool
set -e
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

usage() {
  cat <<'EOF'
usage: scripts/build.sh [--soc esp32s3|esp32s31] [--c src.c …] [--obj o …]
                        [--lib name|file.a …] [--cflags "…"] [fpc options]
                        <prog.pas>

Cross-build a Pascal program for an ESP32-family SoC.

Required environment (this script never guesses host paths):
  ESP_FPC_ROOT       fpc-cross install for THIS build.
                       esp32s3  -> the tree holding lib/fpc/<ver>/ppcrossxtensa
                       esp32s31 -> the tree holding lib/fpc/<ver>/ppcrossrv32
                     e.g.  ESP_FPC_ROOT=$HOME/fpc-cross/fpc-xtensa
                     lib/fpc/etc/fpc.cfg is optional: unit paths, binutils prefix,
                     link closure, FPU mode and libc scheme are all derived here.
  ESP_IDF_VERSION    version string passed as -WP; selects the espidf_<NNN> unit
                     default: 6.1
  ESP32_SDK_PROJECT  a built ESP-IDF project (idf.py build already run):
                     build/bootloader/bootloader.bin, build/partition_table/,
                     build/config/sdkconfig.h. The script additionally links
                     libesp_psram.a (CONFIG_SPIRAM on) and libespcoredump.a
                     (archive present) whole-archive from this project's
                     build tree, so those components must be in the build
                     when the features are enabled
                     e.g.  ESP32_SDK_PROJECT=$HOME/esp/my-idf-project
                     It must also build every component the freertos RTL
                     binding link-lists, because an unbuilt component leaves
                     no archive to link (add them to the app's REQUIRES):
                       esp_phy esp_coex driver vfs mbedtls esp_driver_uart
                       esp_driver_usb_serial_jtag esp_ringbuf

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
  FPU mode          <- (xtensa) ppudump on the installed RTL's system.ppu,
                       passed as -Cfsoft/-Cfhard so it always matches the
                       units; riscv32's float ABI is fixed -Cprv32imafc. The
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
  C compile flags   <- with --c, the command IDF recorded for the project's
                       main/ component in build/compile_commands.json (exact
                       include order, chip codegen flags, defines)

Options:
  --soc esp32s3      xtensa lx7 (default): ppcrossxtensa, -WpESP32S3
  --soc esp32s31     riscv32: ppcrossrv32, -Cprv32imafc, -WpESP32S31
  [fpc options]      forwarded to the compiler; later options win
                     (e.g. -Ch1024 overrides a -Ch from fpc.cfg)
  --help             show this help

C interop (a Pascal program calling C; details in ../AGENTS.md §4):
  --c src.c          compile src.c with the derived cross gcc and link the
                     object; repeatable. The object lands next to the source.
  --obj file.o       link a prebuilt object (repeatable)
  --lib name|file.a  link an archive (repeatable). A bare name is searched in
                     the derived -Fl dirs (lib<name>.a); a path is used as is.
                     Archives are pulled in with --whole-archive, because FPC
                     passes -k arguments before its own objects.
  --cflags "…"       extra C flags appended to the recorded IDF command

Examples:
  export ESP_FPC_ROOT=... ESP32_SDK_PROJECT=...
  scripts/build.sh examples/idfheap-smoke.pas

  # switch SoC: point ESP_FPC_ROOT (and the SDK project) at the riscv32 pair
  ESP_FPC_ROOT=... ESP32_SDK_PROJECT=... \
    scripts/build.sh --soc esp32s31 examples/idfheap-smoke.pas

  # Pascal + C in one build (C symbols declared "cdecl; external")
  scripts/build.sh my-prog.pas --c my-module.c
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
  # $1 = FPC_ROOT, $2 = binary name (ppcrossxtensa | ppcrossrv32)
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
C_SRCS=
C_OBJS=
C_LIBS=
C_FLAGS_EXTRA=
_keep=
while [ $# -gt 0 ]; do
  case "$1" in
    --soc|--c|--obj|--lib|--cflags)
      [ $# -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 1; }
      case "$1" in
        --soc)    soc=$2 ;;
        --c)      C_SRCS="$C_SRCS $2" ;;
        --obj)    C_OBJS="$C_OBJS $2" ;;
        --lib)    C_LIBS="$C_LIBS $2" ;;
        --cflags) C_FLAGS_EXTRA="$C_FLAGS_EXTRA $2" ;;
      esac
      shift 2 ;;
    --help) usage; exit 0 ;;
    *) _keep="$_keep $1"; shift ;;
  esac
done
# Rebuild the pass-through list without pathname expansion, so FPC options that
# contain wildcards (-Fu/path/*) reach the compiler untouched.
set -f
set -- $_keep
set +f

[ $# -ge 1 ] || {
  echo "usage: $(basename "$0") [--soc <name>] [--c <file.c>] [--obj <file.o>]" >&2
  echo "       [--lib <name|file.a>] [--cflags \"…\"] [fpc options] <prog.pas>" >&2
  echo "       run $(basename "$0") --help for the required environment" >&2
  exit 1
}

need_env ESP_FPC_ROOT
need_env ESP32_SDK_PROJECT
FPC_ROOT=$ESP_FPC_ROOT
IDF_VER=${ESP_IDF_VERSION:-6.1}
PRJ=$ESP32_SDK_PROJECT

# --- per-SoC table -----------------------------------------------------------
# PPC_NAME is the binary the FPC makefile actually installs (riscv32 ->
# ppcrossrv32, NOT ppcrossriscv32); TARGET_CPU names the units/<target>-freertos
# dir and gates the -Cf probe below. ABI_OPT carries what the RTL was built
# with that cannot be probed: riscv32 ILP32F = -Cprv32imafc (xtensa's FPU mode
# is probed from the units instead).
case "$soc" in
  esp32s3)
    PPC_NAME=ppcrossxtensa
    TARGET_CPU=xtensa
    MCU=-WpESP32S3
    ABI_OPT=
    ESPTOOL_CHIP=esp32s3
    TOOLCHAIN_NAME=xtensa-esp-elf
    ;;
  esp32s31)
    PPC_NAME=ppcrossrv32
    TARGET_CPU=riscv32
    MCU=-WpESP32S31
    ABI_OPT=-Cprv32imafc
    ESPTOOL_CHIP=esp32s31
    TOOLCHAIN_NAME=riscv32-esp-elf
    ;;
  *)
    echo "unknown SoC: $soc (known: esp32s3 esp32s31)" >&2; exit 1;;
esac

PPC=$(find_ppc "$FPC_ROOT" "$PPC_NAME")
[ -x "$PPC" ] || { echo "cross compiler missing: $PPC" >&2; exit 1; }

# Discover binutils + IDF root from the toolchain's own fpc.cfg -Fl lines
# (env overrides win). No host path defaults. The cfg is optional: a bare
# `make install` carries nothing useful for this target, and a toolchain that is
# mid-rebuild has no cfg at all — the unit search paths are derived below and
# the binutils/IDF locations come from ESP_TOOLCHAIN_BIN or the SDK project.
CFG=$FPC_ROOT/lib/fpc/etc/fpc.cfg
[ -f "$CFG" ] || CFG=
TC_MATCH=
if [ -n "$CFG" ]; then
  TC_MATCH=$(sed -n "s|^ *-Fl\\(.*/$TOOLCHAIN_NAME/[^/]*\\)/$TOOLCHAIN_NAME/.*|\\1|p" "$CFG" 2>/dev/null | head -1)
fi
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
  IDF_PATH=$(sed -n 's|^ *-Fl\(/.*/esp-idf[^/]*\)/.*|\1|p' "${CFG:-/dev/null}" 2>/dev/null | head -1)
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
#    RISC-V ILP32F (esp32s31) keeps picolibc under the multilib path
#    …/rv32imafc_*/ilp32f, not …/lib/<chip>.
if [ -d "$PRJ/build/esp-idf/esp_libc" ]; then
  for d in "$TC_ROOT"/picolibc/*/lib/"$ESPTOOL_CHIP" \
           "$TC_ROOT"/picolibc/*/lib/rv32imafc*/ilp32f; do
    [ -d "$d" ] || continue
    has_libs "$d" || continue
    case " $FL_OPTS " in *" -Fl$d "*) continue;; esac
    FL_OPTS="-Fl$d $FL_OPTS"
  done
fi
# Matching libgcc multilib for ILP32F (soft-float ilp32 would be wrong).
for d in "$TC_ROOT"/lib/gcc/*/*/rv32imafc*/ilp32f; do
  add_fl "$d"
done

# Cross binutils prefix (<prefix>gcc in the binutils dir), so a bare install
# whose fpc.cfg still says -XP$FPCTARGET- (-> "xtensa-freertos-as") works.
# Xtensa installs use chip-qualified names (xtensa-esp32s3-elf-gcc). The
# Espressif RISC-V install is a single triple (riscv32-esp-elf-gcc) shared by
# every RV chip — fall back to that when no *-<chip>-*-gcc exists.
BIN_PREFIX=
for c in "$TC_BIN"/*-"$ESPTOOL_CHIP"-*gcc; do
  [ -x "$c" ] && { BIN_PREFIX=$(basename "$c" gcc); break; }
done
if [ -z "$BIN_PREFIX" ]; then
  for c in "$TC_BIN"/riscv32-esp-elf-gcc "$TC_BIN"/*-esp-elf-gcc; do
    [ -x "$c" ] && { BIN_PREFIX=$(basename "$c" gcc); break; }
  done
fi
[ -n "$BIN_PREFIX" ] || {
  echo "error: ESP_TOOLCHAIN_BIN has no *-$ESPTOOL_CHIP-*-gcc (or riscv32-esp-elf-gcc); it does not match --soc $soc" >&2
  exit 1
}

# FPU mode must match the installed RTL, and a plain fpc.cfg says nothing
# about it (the compiler's built-in default may differ from how the RTL was
# built -> "Trying to use a unit which was compiled with a different FPU
# mode"). Ask the RTL itself via ppudump when that tool is available.
# -Cfsoft/-Cfhard exist on xtensa only; riscv32's float ABI is fixed above.
FPU_OPT=
TARGET_UNITS=
for u in "$FPC_ROOT"/lib/fpc/*/units/"$TARGET_CPU"-freertos/rtl/system.ppu; do
  [ -f "$u" ] && { TARGET_UNITS=$u; break; }
done
PPUDUMP=$(ls "$FPC_ROOT"/bin/ppudump "$FPC_ROOT"/lib/fpc/*/ppudump 2>/dev/null | head -1)
[ -n "$PPUDUMP" ] || PPUDUMP=$(command -v ppudump 2>/dev/null || true)
if [ "$TARGET_CPU" = xtensa ] && [ -n "$PPUDUMP" ] && [ -x "$PPUDUMP" ] && [ -f "$TARGET_UNITS" ]; then
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
# --- C interop --------------------------------------------------------------
# --c compiles a C source with the derived cross gcc and the include set the SDK
# project itself used, then hands the object to FPC's linker; --obj/--lib do the
# same for already-built inputs. Compiler, headers and flags are all derived, so
# the repo still contains no toolchain.
LINK_EXTRA=
if [ -n "$C_SRCS" ]; then
  C_CC="$TC_BIN/${BIN_PREFIX}gcc"
  [ -x "$C_CC" ] || { echo "error: no C compiler at $C_CC (needed by --c)" >&2; exit 1; }
  # Reuse the compile command IDF itself used for main/: it carries the exact,
  # correctly ordered include set (105 dirs here), the chip codegen flags and
  # the defines. Guessing a union of component includes instead picks up the
  # unused Linux-compat component, whose bsd/sys/cdefs.h shadows libc's.
  C_FLAGS=$(python - "$PRJ/build/compile_commands.json" <<'PY'
import json, shlex, sys
try:
    db = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
if not db:
    sys.exit(0)
entry = next((e for e in db if "/main/" in (e.get("file") or "")), db[0])
args = shlex.split(entry.get("command") or " ".join(entry.get("arguments") or []))
out, skip = [], False
for a in args[1:]:            # [0] is the compiler itself
    if skip:
        skip = False
        continue
    if a in ("-o", "-MT", "-MF", "-MJ", "-MQ"):
        skip = True
        continue
    if a in ("-c", "-MD", "-MMD", "-MP") or a.startswith("-o") \
       or a.startswith("-fmacro-prefix-map") or a.startswith("-fdiagnostics"):
        continue
    # Only flags and @response-files: the entry also lists the object path and
    # the source itself as bare arguments.
    if a.startswith("-") or a.startswith("@"):
        out.append(a)
print(" ".join(out))
PY
)
  [ -n "$C_FLAGS" ] || {
    echo "error: --c needs $PRJ/build/compile_commands.json" >&2
    echo "       (idf.py build writes it; run that in $PRJ first)" >&2
    exit 1
  }
  for s in $C_SRCS; do
    [ -f "$s" ] || { echo "error: no such C source: $s" >&2; exit 1; }
    o=${s%.*}.o
    echo "cc $s"
    $C_CC $C_FLAGS -c -o "$o" "$s" $C_FLAGS_EXTRA || exit 1
    C_OBJS="$C_OBJS $o"
  done
fi
for o in $C_OBJS; do
  [ -f "$o" ] || { echo "error: no such object: $o" >&2; exit 1; }
  case "$o" in /*) ;; *) o="$(pwd)/$o" ;; esac
  LINK_EXTRA="$LINK_EXTRA -k$o"
done
for l in $C_LIBS; do
  case "$l" in
    *.a|*/*) p=$l ;;
    *) p=
       for fl in $FL_OPTS; do
         d=${fl#-Fl}
         [ -f "$d/lib$l.a" ] && { p="$d/lib$l.a"; break; }
       done ;;
  esac
  [ -n "$p" ] && [ -f "$p" ] || {
    echo "error: archive not found for --lib $l" >&2
    echo "       searched the derived -Fl dirs; pass a path to the .a instead" >&2
    exit 1
  }
  # FPC hands -k arguments to the linker *before* its own objects, so a plain
  # archive reference would be scanned before anything needs it. Pull every
  # member in instead; for a small C-module archive that is the intended use.
  LINK_EXTRA="$LINK_EXTRA -k--whole-archive -k$p -k--no-whole-archive"
done


# --- SDK-config-dependent link closure (esp_psram, espcoredump) --------------
# The RTL's {$linklib} set carries no SDK-config-dependent archives. The ones
# whose existence depends on the sdkconfig are linked here, keyed on the SDK
# project's own build output -- the identical rule for both SoCs:
#   - libesp_psram.a when the project was built WITH CONFIG_SPIRAM: its
#     startup/heap archives then reference esp_psram_* symbols;
#   - libespcoredump.a whenever the project built it (CONFIG_ESP_COREDUMP_
#     ENABLE): libesp_system.a's panic handling references esp_core_dump_
#     write then. Detected by archive presence, not config keys -- a
#     coredump-disabled project can still carry ENABLE_TO_NONE=y.
# FPC only injects an archive for a {$linklib} in a USED unit, and it hands
# -k arguments to the linker *before* its own objects, so a plain archive
# reference would be scanned before anything needs it (a static archive is
# only scanned once): pull every member in instead -- a few KB each.
CFGH=$PRJ/build/config/sdkconfig.h
if grep -aq '^#define CONFIG_SPIRAM 1' "$CFGH" 2>/dev/null; then
  PSRAM_A=$PRJ/build/esp-idf/esp_psram/libesp_psram.a
  [ -f "$PSRAM_A" ] || {
    echo "SPIRAM sdkconfig detected in $CFGH but $PSRAM_A is missing - rebuild the SDK project first" >&2
    exit 1
  }
  LINK_EXTRA="$LINK_EXTRA -k--whole-archive -k$PSRAM_A -k--no-whole-archive"
fi
COREDUMP_A=$PRJ/build/esp-idf/espcoredump/libespcoredump.a
if [ -f "$COREDUMP_A" ]; then
  LINK_EXTRA="$LINK_EXTRA -k--whole-archive -k$COREDUMP_A -k--no-whole-archive"
fi

# RTL/package unit paths, derived: the cfg is optional (a bare or mid-rebuild
# install may have none), but system / sysutils / classes / Generics.* still
# have to be found. FPC expands the '*' itself, so it stays a single argument.
UNIT_ROOT=
for d in "$FPC_ROOT"/lib/fpc/*/units/"$TARGET_CPU"-freertos; do
  [ -d "$d" ] && { UNIT_ROOT=$d; break; }
done
if [ -n "$UNIT_ROOT" ]; then
  set -- "-Fu$UNIT_ROOT" "-Fu$UNIT_ROOT/*" "$@"
fi

# Repo unit search paths, derived generically: units/ itself plus every one of
# its subdirectories. Nothing in the script hardwires unit names — drop a new
# unit directory there and it is found automatically.
UNIT_DIRS="-Fu$REPO/units"
for d in "$REPO"/units/*/; do
  [ -d "$d" ] && UNIT_DIRS="$UNIT_DIRS -Fu${d%/}"
done

# -Tfreertos + -Wp<MCU> + -WP<IDF ver>; units/ via -Fu. Later options win, so
# user-supplied options still override -XP/dirs. $FL_OPTS/$LINK_EXTRA/
# $UNIT_DIRS are deliberately unquoted: they are space-separated option lists
# built above.
exec "$PPC" -Tfreertos "$MCU" "-WP$IDF_VER" "-XP$BIN_PREFIX" $ABI_OPT $FPU_OPT \
  $UNIT_DIRS $FL_OPTS $LINK_EXTRA "$@"
