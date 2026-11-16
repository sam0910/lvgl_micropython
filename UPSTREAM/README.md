# UPSTREAM — keeping CSMB settings across MicroPython / LVGL updates

This folder holds every file I changed **by hand** in this repo and its
submodules, so the settings survive when `lib/micropython` or `lib/lvgl` is
moved to a newer version (or when upstream `lvgl_micropython` is merged in).

Saved against: **MicroPython master `350908a`** (1.30.0-preview), **LVGL v9.6.0**.
`lv_conf.h.patch` is relative to `upstream/main` (lvgl-micropython).

## What is saved

| File (path in the repo) | My change |
|---|---|
| `lib/lv_conf.h` | LVGL config: 16-bit color, 300 KB image cache, logs off, custom fonts via `#include "my_fonts.h"`, default font Montserrat 12, compressed fonts, MEMFS on `M:`, obj property/name on, Calendar/Win/BMP/Pinyin off, … |
| `lib/micropython/ports/esp32/boards/sdkconfig.base` | The `# CSMB Custom settings` block at the end (PSRAM XIP, octal SPIRAM 120 MHz, QIO flash 120 MHz 16 MB, 240 MHz CPU, 1000 Hz FreeRTOS tick, `-O2` perf, S3 cache tuning) |
| `lib/micropython/ports/esp32/boards/ESP32_GENERIC_S3/mpconfigboard.h` | Board name `STELLA ESP32S3`; USB device / USB CDC / USB-Serial-JTAG disabled |
| `lib/micropython/ports/esp32/boards/ESP32_GENERIC_S3/mpconfigvariant_SPIRAM_OCT.cmake` | Board name `STELLA ESP32S3 with Octal-SPIRAM` |

Each one is kept in two forms:

- `files/…` — full copy of the file, at the same path as in the repo. Use it as
  the reference when a patch doesn't apply.
- `patches/` — only my changes, as git diffs:
  - `patches/micropython.patch` — the three files under `lib/micropython` (apply inside the submodule)
  - `patches/lv_conf.h.patch` — `lib/lv_conf.h` (apply from the repo root)

## What is NOT saved (the build regenerates it)

These also show up as modified after a build, but a script writes them every
time, so do **not** copy or patch them:

| File | Written by |
|---|---|
| `lib/micropython/py/mkrules.cmake` (`list(REMOVE_DUPLICATES MICROPY_CPP_FLAGS)`) | `update_mkrules()` in `builder/esp32.py` |
| `sdkconfig.base`: `CONFIG_FREERTOS_INTERRUPT_BACKTRACE=n` and `CONFIG_FREERTOS_IDLE_TASK_STACKSIZE=4096` | `builder/esp32.py` (~line 679) |
| other files in `lib/micropython/ports/esp32/` (`main.c`, `mpthreadport.*`, `mpconfigport.h`, panic handler, …) | `builder/esp32.py` (copies from `micropy_updates/esp32/` and edits in place) |
| `lib/lvgl/lvgl.h` (`#include "my_images.h"`), `lib/lvgl/my_images.h`, `lib/lvgl/src/ex_*.c`, `lib/lvgl/src/font/lv_font_*.c` | `build.sh` |
| `lib/my_fonts.h` | `build.sh` |

> `lib/lv_conf.h` includes `my_fonts.h`, so **run `build.sh`** (or at least its
> font step) before `make.py`, otherwise the build fails with a missing header.
> `build.sh` is not in this repo: it is `/Volumes/ORICO/CSMB/firmware/build.sh`.

## How to update MicroPython / LVGL and keep the settings

Run everything from the repo root (`lvgl_micropython/`).

**Steps 1-4 are automated by `UPSTREAM/APPLY.sh`:**

```sh
UPSTREAM/APPLY.sh v1.30.0 v9.6.1      # MicroPython ref, LVGL ref (tag or branch)
UPSTREAM/APPLY.sh - release/v9.6      # "-" keeps the current version
```

It stops if your live settings aren't saved in this folder yet (`FORCE=1` skips
that check). It then resets and moves the submodules, re-applies both patches,
lists `lv_conf.h` options the new LVGL template added or removed, and checks
that your `CONFIG_…` options exist in `lib/esp-idf`. It exits non-zero if
anything needs fixing by hand. It does not change `builder/esp32.py` or `gen/`,
and it does not build. The manual steps below are what it does.

### 1. Reset the submodules to clean upstream files

This throws away all local edits in the submodules. My edits are safe in this
folder, and the build/`build.sh` changes come back on the next build.

```sh
git -C lib/micropython checkout -- .
git -C lib/lvgl checkout -- .
```

Untracked files that `build.sh` generated (`lib/lvgl/src/ex_*.c`, fonts,
`my_images.h`) stay where they are. That's fine, `build.sh` overwrites them.

### 2. Move the submodules to the new versions

The submodules are shallow clones, so fetch the tag you want first
(replace `vX.Y.Z` with the new tag):

```sh
git -C lib/micropython fetch --depth 1 origin tag vX.Y.Z
git -C lib/micropython checkout vX.Y.Z

git -C lib/lvgl fetch --depth 1 origin tag vX.Y.Z
git -C lib/lvgl checkout vX.Y.Z
```

A new version usually needs other changes too (ESP-IDF version in
`builder/esp32.py`, binding generator fixes in `gen/`, …). `../MODIFICATION.md`
describes those for the 1.29 / 9.6 update. Do that part as well.

### 3. Re-apply the MicroPython board settings

```sh
git -C lib/micropython apply --3way ../../UPSTREAM/patches/micropython.patch
```

- No output = applied cleanly.
- `--3way` stages the result. Run `git -C lib/micropython reset -q` afterwards,
  otherwise `git diff` (used by step 6 and the refresh script) doesn't show it.
- `--3way` merges the changes into an upstream file that has moved. If that
  produces conflicts, fix the `<<<<<<<` markers by hand. Use the full copies in
  `UPSTREAM/files/lib/micropython/…` as the reference.
- If it fails with "lacks the necessary blob", the old upstream version isn't in
  the submodule any more. Apply the changes by hand from the table above. The
  `sdkconfig.base` change is a plain block appended at the end of the file.
- Check that the settings still exist in the new ESP-IDF. A renamed `CONFIG_…`
  option is ignored without an error. Look it up in
  `build/…/sdkconfig` after the first build.

### 4. Check `lib/lv_conf.h`

`lib/lv_conf.h` belongs to this repo, not a submodule, so step 2 does not touch
it. Two cases need work:

- **New LVGL version:** compare `lib/lv_conf.h` with the new
  `lib/lvgl/lv_conf_template.h`. Add any new options and remove any that were
  renamed or deleted (example: LVGL 9.6 needs `LV_USE_OBJ_NAME 1` when
  `LV_USE_OBJ_PROPERTY` is 1).
- **Merged a newer upstream `lvgl_micropython` that replaced `lv_conf.h`:**
  re-apply my settings on top of the new file:

  ```sh
  git apply --3way UPSTREAM/patches/lv_conf.h.patch
  ```

  Then `git reset -q lib/lv_conf.h` to unstage it. If it conflicts, resolve it
  against `UPSTREAM/files/lib/lv_conf.h`.

### 5. Build

Run `/Volumes/ORICO/CSMB/firmware/build.sh` as usual. It regenerates the images/fonts and the `lvgl.h`
include, and `builder/esp32.py` re-applies its own edits.

### 6. Verify

```sh
git -C lib/micropython diff --stat   # 3 board files from the patch + builder files
git diff --stat lib/lv_conf.h
```

Flash and check the board name in the REPL banner: `STELLA ESP32S3 with Octal-SPIRAM`.

## After changing my settings: refresh this folder

Run this from the repo root after editing any of the four files, so the copies
and patches stay current. It removes the two builder lines from
`sdkconfig.base` before saving it.

```sh
B=lib/micropython/ports/esp32/boards
cp lib/lv_conf.h UPSTREAM/files/lib/
cp $B/ESP32_GENERIC_S3/mpconfigboard.h $B/ESP32_GENERIC_S3/mpconfigvariant_SPIRAM_OCT.cmake \
   UPSTREAM/files/$B/ESP32_GENERIC_S3/
python3 -c "
p='$B/sdkconfig.base'
s=open(p).read().replace('\nCONFIG_FREERTOS_INTERRUPT_BACKTRACE=n\nCONFIG_FREERTOS_IDLE_TASK_STACKSIZE=4096\n','',1)
open('UPSTREAM/files/'+p,'w').write(s)"

git diff --full-index upstream/main -- lib/lv_conf.h > UPSTREAM/patches/lv_conf.h.patch
cp $B/sdkconfig.base /tmp/sdkconfig.base.bak
cp UPSTREAM/files/$B/sdkconfig.base $B/sdkconfig.base
git -C lib/micropython diff --full-index -- ports/esp32/boards > UPSTREAM/patches/micropython.patch
cp /tmp/sdkconfig.base.bak $B/sdkconfig.base && rm /tmp/sdkconfig.base.bak
```

If you change another file by hand (in a submodule or not), add it to the
table above, copy it into `files/` and include it in the matching patch.
