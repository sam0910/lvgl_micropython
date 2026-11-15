## This is base on the instrucions from, 

['A guide for integrating LVGL v9.6 as a module in MicroPython v1.29'](https://forum.lvgl.io/t/a-guide-for-integrating-lvgl-v9-6-as-a-module-in-micropython-v1-29/24494) by jgpeiro



---
## Updating [lvgl_micropython](https://github.com/lvgl-micropython/lvgl_micropython) by kdschlosser, to MicroPython 1.29 and LVGL 9.6

This guide is for users of the upstream repository
[lvgl-micropython/lvgl_micropython](https://github.com/lvgl-micropython/lvgl_micropython).
It explains what to change so that `make.py` builds firmware with the latest
MicroPython and LVGL instead of the versions the repository ships with.

| Component | Upstream repo uses | This guide moves to |
|---|---|---|
| MicroPython | v1.27.0 | **v1.29.0** |
| LVGL | v9.4.0 | **v9.6.0** |
| ESP-IDF | v5.5.1 | **v5.5.2** (the version MicroPython 1.29 recommends) |

The steps were tested on upstream `main` at commit `d2d2646`
("Merge pull request #585 from FreakStudioCN/main"), building an ESP32-S3
firmware on macOS. If upstream has moved on since then, line numbers may
differ but the changes are the same.

---


## 1. How the repository is put together

`make.py` is only the entry point. **`make.py` itself needs no changes.** The
version-specific parts live elsewhere:

| What | Location in the repo | How it gets there | What pins the version |
|---|---|---|---|
| MicroPython source | `lib/micropython` | git submodule, fetched by `make.py` if `lib/micropython/mpy-cross` is missing | the submodule commit |
| LVGL source | `lib/lvgl` | git submodule, fetched by `make.py` if `lib/lvgl/lvgl.h` is missing | the submodule commit |
| ESP-IDF | `lib/esp-idf` (or your own via `IDF_PATH`) | git submodule, fetched and installed by `builder/esp32.py` | the submodule commit + `IDF_VER` in `builder/esp32.py` |
| pycparser | `lib/pycparser` | git submodule | unchanged |
| LVGL config | `lib/lv_conf.h` | in the repo | unchanged, works with 9.6 |
| LVGL to Python binding generator | `gen/python_api_gen_mpy.py`, `gen/fixed_gen_json.py` | in the repo | needs 2 fixes |
| LVGL C module build rules | `ext_mod/lvgl/micropython.cmake` | in the repo | unchanged |
| ESP32 build logic | `builder/esp32.py` | in the repo | needs `IDF_VER` update |
| Display/touch drivers (Python) | `api_drivers/` | in the repo | 1 small rename |

What happens when you run `python3 make.py esp32 ...`:

1. `make.py` fetches missing submodules (`get_submodules()`).
2. `builder/esp32.py` copies its replacement files from `micropy_updates/esp32/`
   into `lib/micropython/ports/esp32`, and fetches/installs ESP-IDF if needed.
3. It writes the frozen-module manifest (`build/manifest.py`) with your
   `DISPLAY` and `INDEV` drivers, and `build/lvgl_header.h`.
4. It runs MicroPython's ESP32 `make` with `USER_C_MODULES=ext_mod/micropython.cmake`.
   During CMake configure, `ext_mod/lvgl/micropython.cmake` runs
   `gen/python_api_gen_mpy.py`, which parses the LVGL headers and writes the
   `lvgl` module (`lv_mp.c`) into the build folder.
5. It merges everything into one `.bin` in `build/`.

You do **not** need `lv_binding_micropython`, even if you followed the LVGL
forum guide for MicroPython 1.29. This repository has its own generator in
`gen/` and its own C module in `ext_mod/lvgl/`.

---

## 2. Prerequisites

- macOS or Linux. Windows is not supported by `make.py`.
- macOS: `xcode-select --install`, then `brew install cmake ninja python`.
- Ubuntu/Debian: `sudo apt-get install git build-essential cmake ninja-build python3 python3-venv python3-pip libusb-1.0-0-dev`
- Python 3.10 or newer (tested with 3.15).
- About 6 GB of free disk space: ~1.3 GB of sources in `lib/`, ~3.5 GB of
  ESP-IDF tools in `~/.espressif/`, ~0.5 GB of build output.

---

## 3. Get the repository

```sh
git clone https://github.com/lvgl-micropython/lvgl_micropython.git
cd lvgl_micropython
```

Do **not** clone with `--recursive`. The ESP-IDF submodule alone is several GB
with all its nested submodules. `make.py` fetches only what it needs.

---

## 4. Get the latest sources

Pick **one** of the two methods. Method A is the one that was tested.

### Method A (recommended): point the submodules at the new versions

These commands change which commit each submodule points to, without
downloading anything yet. Run them from the repository root:

```sh
# MicroPython v1.29.0
git update-index --cacheinfo 160000,0fd6c573ea815774668bbb16b8e197c8822368b2,lib/micropython
# LVGL v9.6.0
git update-index --cacheinfo 160000,80ca777e37a2b176770726a02e07a6fb79ef0b39,lib/lvgl
# ESP-IDF v5.5.2
git update-index --cacheinfo 160000,30aaf64524299d3bde422ca9a2848090d1bc5d0f,lib/esp-idf
```

Then download MicroPython, LVGL and pycparser (shallow, so only the pinned
commit is fetched):

```sh
git submodule update --init --depth=1 -- lib/micropython lib/lvgl lib/pycparser
```

Check the versions:

```sh
git -C lib/micropython log --oneline -1   # 0fd6c57 all: Bump version to 1.29.0.
git -C lib/lvgl log --oneline -1          # 80ca777 chore: release v9.6.0 (#10713)
```

Leave `lib/esp-idf` alone. The first build fetches ESP-IDF v5.5.2 at the
pinned commit, with only the nested submodules it needs, and installs the
toolchains.

To look up the commit of a tag yourself (for example for a later release):

```sh
git ls-remote https://github.com/micropython/micropython.git 'refs/tags/v1.29.0^{}'
git ls-remote https://github.com/lvgl/lvgl.git 'refs/tags/v9.6.0'
git ls-remote https://github.com/espressif/esp-idf.git 'refs/tags/v5.5.2^{}'
```

Use the `^{}` line when there is one (annotated tags). LVGL's tags have no
`^{}` line, so use the plain one.

### Method B: clone the sources yourself into `lib/`

Use this if you prefer to fetch the sources by hand. Each source must be a
**git clone**, not a downloaded zip, because the build runs `git` inside
`lib/micropython` (to fetch its own submodules and to read the version tag).

| Source | Copy to | Command (from the repository root) |
|---|---|---|
| MicroPython v1.29.0 | `lib/micropython` | `git clone --depth 1 -b v1.29.0 https://github.com/micropython/micropython.git lib/micropython` |
| LVGL v9.6.0 | `lib/lvgl` | `git clone --depth 1 -b v9.6.0 https://github.com/lvgl/lvgl.git lib/lvgl` |
| ESP-IDF v5.5.2 | `lib/esp-idf` | `git clone --depth 1 -b v5.5.2 --recursive --shallow-submodules https://github.com/espressif/esp-idf.git lib/esp-idf` |
| pycparser | `lib/pycparser` | `git submodule update --init --depth=1 -- lib/pycparser` (same version as before) |

The target folders must be empty (they are, in a fresh clone).

Notes for Method B:

- **ESP-IDF must be cloned with `--recursive`.** When `lib/esp-idf/export.sh`
  already exists, the builder skips its own download step, which is also the
  step that fetches the nested submodules (lwip, mbedtls, Wi-Fi and Bluetooth
  libraries, esptool). Without them the build fails.
- **If you already have ESP-IDF v5.5.2 installed elsewhere**, you can skip
  `lib/esp-idf` and set `export IDF_PATH=/path/to/esp-idf` before running
  `make.py`. The builder uses `IDF_PATH` only when that ESP-IDF reports
  version 5.5.2 (it compares against `IDF_VER` in `builder/esp32.py`).
- **Record the new versions in git** so a later `git submodule update` does
  not switch you back to the old ones:

  ```sh
  git add lib/micropython lib/lvgl lib/esp-idf
  ```

### If your checkout has already built the old version

Do this once before building with the new sources:

```sh
# throw away the builder's in-place edits in the old MicroPython tree
git -C lib/micropython checkout -- .
# run the three "git update-index" commands from Method A, then:
git submodule update --init --depth=1 -- lib/micropython lib/lvgl
# unload the old ESP-IDF so the build fetches v5.5.2 together with
# the matching versions of its nested submodules (lwip, mbedtls, ...)
git submodule deinit -f lib/esp-idf
# remove stale backups the builder keeps while it patches MicroPython files
rm -rf micropy_updates/originals
```

Do not just run `git submodule update` on `lib/esp-idf` in an existing
checkout: that moves ESP-IDF itself to v5.5.2 but leaves its nested
submodules at the v5.5.1 versions, and the builder will not refresh them.

Always build with `clean` the first time after switching (section 6). The
ESP-IDF toolchains in `~/.espressif` are versioned, so the old and new ones
can live side by side.

---

## 5. Edit the code

Five small edits. Items 1 to 3 are required for the build to succeed.

### 5.1 `builder/esp32.py`: ESP-IDF version (required)

Line 19:

```python
IDF_VER = '5.5.1'
```

becomes:

```python
IDF_VER = '5.5.2'
```

`IDF_VER` decides whether an ESP-IDF given through `IDF_PATH` is accepted, and
where the builder looks for the ESP-IDF Python environment after the build
(`~/.espressif/python_env/idf5.5_py3.X_env`).

If your `python3` is **3.15 or newer**, also add your version to the list in
`compile()` (around line 1587), or the build ends with
`unable to locate python version used in the ESP-IDF` right after compiling:

```python
for ver in ('3.8', '3.9', '3.10', '3.11', '3.12', '3.13', '3.14', '3.15'):
```

Optional, cosmetic: update the messages `collecting ESP-IDF v5.5.1` and
`setting up ESP-IDF v5.5.1` to `v5.5.2`.

### 5.2 `gen/python_api_gen_mpy.py`: MicroPython 1.29 API change (required)

MicroPython 1.29 removed the internal function `mp_obj_int_to_bytes_impl()`.
The generator still writes a call to it into `lv_mp.c`, which fails to compile
with an implicit declaration error.

In the C template inside the generator (function `mp_obj_get_ull`, around line
2083), replace:

```c
    mp_obj_int_to_bytes_impl(obj, big_endian, sizeof(val), (byte*)&val);
```

with:

```c
    mp_obj_int_to_bytes(obj, sizeof(val), (byte*)&val, big_endian, false, false);
```

Make the same change in `gen/lvgl_api_gen_mpy.py` (around line 1963). That
file is the alternative generator; `make.py` uses `python_api_gen_mpy.py` by
default (`GEN_SCRIPT=python`), but keeping both in sync avoids surprises.

One-liner for both files (macOS `sed`; on Linux drop the `''` after `-i`):

```sh
sed -i '' 's|mp_obj_int_to_bytes_impl(obj, big_endian, sizeof(val), (byte\*)&val);|mp_obj_int_to_bytes(obj, sizeof(val), (byte*)\&val, big_endian, false, false);|' \
    gen/python_api_gen_mpy.py gen/lvgl_api_gen_mpy.py
```

### 5.3 `gen/fixed_gen_json.py`: negative enum values in LVGL 9.6 (required)

The generator uses LVGL's own `lib/lvgl/scripts/gen_json/pycparser_monkeypatch.py`
to read the headers. LVGL 9.6 exports a negative constant (`LV_COORD_MIN`),
and that script formats enum values with `hex(value)[2:]`, which turns
`-0x1FFFFFFF` into `x1FFFFFFF`. The binding generation then stops with:

```
ValueError: invalid literal for int() with base 16: '0xX1FFFFFFF'
```

and the CMake step reports `Failed to generate .../lv_mp.c`.

Fix it without touching the LVGL submodule. In `gen/fixed_gen_json.py`, right
after the line `pycparser_monkeypatch.get_macros = dummy_list`, add:

```python
# LVGL's Enum.to_dict() formats values with hex(value)[2:], which breaks on
# negative enum values (LV_COORD_MIN in LVGL 9.6). Shadow hex() in that module
# with a 32 bit two's complement version.
pycparser_monkeypatch.hex = lambda value: hex(value & 0xFFFFFFFF if value < 0 else value)
```

These values only go into the JSON metadata, not into the generated C code,
so this has no effect on the firmware's behaviour.

### 5.4 `api_drivers/py_api_drivers/frozen/display/display_driver_framework.py` (optional)

LVGL 9.5 renamed `lv_display_delete_event` to `lv_display_remove_event`. The
driver's `delete_event()` wrapper would raise `AttributeError` if you call it.
Around line 382, replace:

```python
        return self._disp_drv.delete_event(index)
```

with:

```python
        return self._disp_drv.remove_event(index)
```

Nothing in the repository calls this method itself, so the build works without
this change.

### 5.5 `builder/__init__.py` (optional, cosmetic)

Update the messages `collecting LVGL v9.4.0` and `collecting MicroPython 1.27.0`
to `v9.6.0` and `1.29.0`.

### What does not need changing

- `make.py`
- `lib/lv_conf.h`. It still works with LVGL 9.6. You will see deprecation
  warnings (section 7).
- `ext_mod/` (lcd_bus, spi3wire, the LVGL module CMake file). They compile
  against MicroPython 1.29 and ESP-IDF 5.5.2 unchanged.
- `micropy_updates/esp32/` (the replacement `machine_hw_spi.c` and
  `machine_sdcard.c`). They compile against MicroPython 1.29 unchanged.
- From the LVGL forum guide: the `lv_binding_micropython` patches, the
  `usermods/` CMake files, the `esp32_common.cmake` edit for `esp_lcd`, and the
  custom board/partition files. This repository handles all of these itself
  (the partition table comes from `--flash-size`, `--ota` and
  `--partition-size`).

---

## 6. Build

Example for an ESP32-S3 module with 16 MB flash and octal PSRAM, an ST7789
display and an FT6x36 touch controller:

```sh
python3 make.py esp32 clean BOARD="ESP32_GENERIC_S3" BOARD_VARIANT="SPIRAM_OCT" \
    --flash-size="16" --ota \
    --partition-size="4194304" --skip-partition-resize \
    DISPLAY="st7789" INDEV="ft6x36"
```

- `BOARD_VARIANT="SPIRAM_OCT"` is for octal PSRAM modules (for example N16R8).
  Leave it out for quad PSRAM modules (for example N8R2).
- `--partition-size="4194304"` makes each OTA app partition 4 MiB.
- `DISPLAY` / `INDEV` names are the folder and file names in
  `api_drivers/common_api_drivers/display/` and `.../indev/`.
- All other options are described in `README.md`.

The first run fetches ESP-IDF v5.5.2 into `lib/esp-idf`, installs its
toolchains into `~/.espressif/`, fetches MicroPython's own submodules, then
compiles about 2,500 files. On an Apple Silicon Mac with a fast connection
this took about 11 minutes in total.

A successful build ends with:

```
micropython.bin binary size 0x25e990 bytes. Smallest app partition is 0x400000 bytes. 0x1a1670 bytes (41%) free.
Project build complete. ...
Wrote 0x27e990 bytes to file .../build/lvgl_micropy_ESP32_GENERIC_S3-SPIRAM_OCT-16.bin, ready to flash to offset 0x0
```

followed by the exact command to flash it.

---

## 7. Check the result

On your computer, before flashing:

```sh
cd lib/micropython/ports/esp32/build-ESP32_GENERIC_S3-SPIRAM_OCT
grep -E "^CONFIG_SPIRAM=|CONFIG_SPIRAM_MODE_OCT=|CONFIG_ESPTOOLPY_FLASHSIZE=|CONFIG_IDF_INIT_VERSION" sdkconfig
# CONFIG_IDF_INIT_VERSION="5.5.2"
# CONFIG_ESPTOOLPY_FLASHSIZE="16MB"
# CONFIG_SPIRAM=y
# CONFIG_SPIRAM_MODE_OCT=y
ls -la lv_mp.c          # about 1.6 MB; the generated lvgl module
```

Flash the `.bin` from `build/` at offset `0x0` with the command `make.py`
prints. That command includes `--erase-all`, which **wipes the board's
filesystem**. Back up your files first.

On the board:

```python
>>> import sys
>>> sys.version
'3.4.0; MicroPython v1.29.0-dirty on ...'
>>> import lvgl as lv
>>> lv.version_major(), lv.version_minor(), lv.version_patch()
(9, 6, 0)
```

The `-dirty` suffix is normal: the builder patches a few files inside
`lib/micropython` while it builds.

---

## 8. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `ValueError: invalid literal for int() with base 16: '0xX1FFFFFFF'`, then `Failed to generate .../lv_mp.c` | Section 5.3 is missing. |
| `implicit declaration of function 'mp_obj_int_to_bytes_impl'` | Section 5.2 is missing. |
| Firmware still reports MicroPython 1.27 or LVGL 9.4 | The submodules were not switched. Check with `git -C lib/micropython log --oneline -1` and `git -C lib/lvgl log --oneline -1`, then redo section 4 and build with `clean`. |
| `unable to locate python version used in the ESP-IDF` after `Project build complete` | Add your Python version to the list in `builder/esp32.py` (section 5.1). The firmware itself is already built in `lib/micropython/ports/esp32/build-*`. |
| Submodule checkout fails with "Your local changes would be overwritten" | The builder's edits from an older build are still in `lib/micropython`. Run `git -C lib/micropython checkout -- .` and retry. |
| Build fails with missing lwip/mbedtls/esp_wifi files when using Method B | ESP-IDF was cloned without `--recursive`. Re-clone it as shown in Method B. |
| Thousands of `#warning ... is deprecated` lines | LVGL 9.6 reporting old option names in `lib/lv_conf.h` (`LV_COLOR_DEPTH`, `LV_ASSERT_HANDLER_INCLUDE`, the calendar name lists). Harmless. |
| `AttributeError` on an `lv.*` name at runtime | The function was renamed in LVGL 9.5/9.6, or the feature is disabled in `lib/lv_conf.h`. Use `dir(lv)` to find the current name; old-to-new mappings are in `lib/lvgl/include/lvgl/api_map/`. |
| `Error: app partition is too small` | Increase `--partition-size`, or on non-OTA builds leave out `--partition-size` and `--skip-partition-resize` so the builder sizes it automatically. |

---

## 9. Known limitations

- Tested only for the ESP32 target with `ESP32_GENERIC_S3` / `SPIRAM_OCT`.
  Other ports (unix, rp2, stm32, ...) use the same generator fixes but were not
  built.
- The firmware has not yet been tested on hardware with these versions.
- The display driver framework methods `set_physical_horizontal_resolution()`
  and `set_physical_vertical_resolution()` call LVGL functions that do not
  exist in 9.6. Nothing in the repository calls them, so they only matter if
  your own code does.
