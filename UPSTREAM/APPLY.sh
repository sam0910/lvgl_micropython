#!/usr/bin/env bash
# Move lib/micropython and lib/lvgl to newer versions and re-apply the CSMB
# settings saved in UPSTREAM/. Automates steps 1-4 of UPSTREAM/README.md.
#
# Usage: UPSTREAM/APPLY.sh [MICROPYTHON_REF] [LVGL_REF]
#   REF: a tag (v1.30.0), a branch (release/v9.6), or "-" to keep the current version.
#   No arguments: only reset the submodules and re-apply the settings.
#   FORCE=1: skip the check that the live settings are saved in UPSTREAM/.
#   UPSTREAM/APPLY.sh v1.30.0 release/v9.6
#
# It does not build, commit, or change builder/esp32.py (IDF_VER) or gen/.

set -euo pipefail

cd "$(dirname "$0")/.."
U=$PWD/UPSTREAM
MP=lib/micropython
LV=lib/lvgl
IDF=lib/esp-idf
B=ports/esp32/boards
MP_REF=${1:--}
LV_REF=${2:--}
status=0

# builder/esp32.py inserts these two lines (plus a blank line) into sdkconfig.base
# on every build, so they are not part of my settings.
strip_builder() {
    grep -vxE 'CONFIG_FREERTOS_(INTERRUPT_BACKTRACE=n|IDLE_TASK_STACKSIZE=4096)' "$1" | grep -v '^$' || true
}

lv_names() {
    sed -nE 's/^[[:space:]]*#[[:space:]]*define[[:space:]]+(LV_[A-Z0-9_]+).*/\1/p' "$1" | sort -u
}

# $1 repo dir, $2 patch, $3 path to unstage
apply_patch() {
    git -C "$1" apply "$2" 2>/dev/null && return 0
    git -C "$1" apply --3way "$2" || return 1
    # --3way stages the result; unstage it so 'git diff' (README refresh step) still sees it.
    git -C "$1" reset -q -- "$3"
}

# $1 submodule, $2 ref. The submodules are shallow, so fetch the ref first.
move() {
    [ "$2" = - ] && return 0
    echo "== $1 -> $2"
    if git -C "$1" fetch -q --depth 1 origin tag "$2" 2>/dev/null; then
        git -C "$1" checkout -q "$2"
    else
        git -C "$1" fetch -q --depth 1 origin "$2"
        git -C "$1" checkout -q FETCH_HEAD
    fi
}

echo "== Check that the live settings are saved in UPSTREAM/"
if [ "${FORCE:-0}" != 1 ]; then
    for f in lib/lv_conf.h $MP/$B/sdkconfig.base \
             $MP/$B/ESP32_GENERIC_S3/mpconfigboard.h \
             $MP/$B/ESP32_GENERIC_S3/mpconfigvariant_SPIRAM_OCT.cmake; do
        if ! cmp -s <(strip_builder "$f") <(strip_builder "$U/files/$f"); then
            echo "ERROR: $f differs from UPSTREAM/files/$f"
            echo "Save it first (README: 'refresh this folder'), or rerun with FORCE=1."
            exit 1
        fi
    done
fi

old_tpl=$(mktemp)
trap 'rm -f "$old_tpl"' EXIT
cp $LV/lv_conf_template.h "$old_tpl"

echo "== Reset submodules to clean upstream files"
git -C $MP reset -q --hard
git -C $LV reset -q --hard

move $MP "$MP_REF"
move $LV "$LV_REF"

echo "== Re-apply MicroPython board settings"
if apply_patch $MP "$U/patches/micropython.patch" $B; then
    echo "OK"
else
    echo "CONFLICT: fix the <<<<<<< markers in $MP/$B, using UPSTREAM/files/$MP/$B as reference."
    status=1
fi

echo "== Check lib/lv_conf.h"
if grep -q '#include "my_fonts.h"' lib/lv_conf.h; then
    echo "OK, already has my settings"
elif apply_patch . "$U/patches/lv_conf.h.patch" lib/lv_conf.h; then
    echo "OK, re-applied lv_conf.h.patch"
else
    echo "CONFLICT: fix the <<<<<<< markers in lib/lv_conf.h, using UPSTREAM/files/lib/lv_conf.h as reference."
    status=1
fi

if [ "$LV_REF" != - ]; then
    new=$(comm -13 <(lv_names "$old_tpl") <(lv_names $LV/lv_conf_template.h) | tr '\n' ' ')
    gone=$(comm -23 <(lv_names "$old_tpl") <(lv_names $LV/lv_conf_template.h) |
           comm -12 - <(lv_names lib/lv_conf.h) | tr '\n' ' ')
    echo "New options in lv_conf_template.h (default from lv_conf_internal.h unless added):"
    echo "  ${new:-none}"
    echo "Set in lib/lv_conf.h but gone from the template (renamed or removed, fix by hand):"
    echo "  ${gone:-none}"
    [ -n "$gone" ] && status=1
fi

echo "== Check my sdkconfig options exist in ESP-IDF $(git -C $IDF describe --tags)"
kconf=$(grep -rhoE '^[[:space:]]*(menu)?config[[:space:]]+[A-Z0-9_]+' $IDF/Kconfig $IDF/components \
        --include='Kconfig*' | awk '{print $2}' | sort -u)
missing=0
for opt in $(sed -n '/# CSMB Custom settings/,/# CSMB Custom settings/p' $MP/$B/sdkconfig.base |
             sed -nE 's/^CONFIG_([A-Z0-9_]+)=.*/\1/p'); do
    if ! grep -qx "$opt" <<<"$kconf"; then
        echo "MISSING: CONFIG_$opt (ignored by the build without an error)"
        grep -rhw "CONFIG_$opt" $IDF/components --include='sdkconfig.rename*' | sed 's/^/  rename: /' || true
        missing=1
    fi
done
[ $missing = 0 ] && echo "OK" || status=1
grep -q "IDF_VER = '$(git -C $IDF describe --tags | sed 's/^v//')'" builder/esp32.py ||
    echo "NOTE: builder/esp32.py IDF_VER differs from $IDF; the check above used $IDF."

echo "== Result"
echo "micropython: $(git -C $MP describe --tags --always)"
echo "lvgl:        $(git -C $LV describe --tags --always)"
[ $status = 0 ] && echo "Settings applied." || echo "Fix the problems above before building."
echo "Next: other changes the new version needs (IDF_VER in builder/esp32.py, gen/, see MODIFICATION.md),"
echo "then run /Volumes/ORICO/CSMB/firmware/build.sh and check the banner says 'STELLA ESP32S3 with Octal-SPIRAM'."
exit $status
