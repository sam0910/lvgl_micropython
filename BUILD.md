# Building the firmware (MicroPython 1.29 + LVGL 9.6)

This guide walks you through building an ESP32-S3 firmware with LVGL
compiled in, starting from a fresh clone of this repository. You do not need
to install ESP-IDF, MicroPython or LVGL yourself: `make.py` downloads and sets
up everything on the first run.

| Component | Version |
|---|---|
| MicroPython | v1.29.0 |
| LVGL | v9.6.0 |
| ESP-IDF | v5.5.2 |

The result is a single `.bin` file you flash at offset `0x0`. On the board,
`import lvgl as lv` gives you the full LVGL API, plus the display and touch
drivers you chose at build time.

---

## 1. What you need

### Operating system

- **macOS** (Intel or Apple Silicon) or **Linux** (Ubuntu or similar).
- **Windows is not supported.** `make.py` stops with an error on Windows.

### Tools

macOS:

```sh
xcode-select --install          # compiler, make and git
brew install cmake ninja python
```

Ubuntu / Debian:

```sh
sudo apt-get update
sudo apt-get install git build-essential cmake ninja-build \
                     python3 python3-venv python3-pip libusb-1.0-0-dev
```

- **Python 3.10 or newer.** The firmware described here was built with
  Python 3.15.
- The stock `make` on macOS (GNU Make 3.81) works. You do not need `gmake`.

### Disk space and time

The first build downloads a lot. Plan for about **6 GB free**:

| What | Where | Size |
|---|---|---|
| ESP-IDF, MicroPython, LVGL sources | `lib/` in this repo | ~1.3 GB |
| ESP-IDF toolchains and Python env | `~/.espressif/` | ~3.5 GB |
| Build output | `lib/micropython/ports/esp32/build-*` | ~0.5 GB |

On an Apple Silicon Mac with a fast connection, the first full build took
about **11 minutes**, downloads included. Slower machines or connections take
longer. Later builds skip the downloads and are much faster.

---

## 2. Get the repository

```sh
git clone https://github.com/sam0910/lvgl_micropython.git
cd lvgl_micropython
```

> **Do not use `git clone --recursive`.** The `lib/esp-idf` submodule alone has
> dozens of nested submodules and is several GB. `make.py` fetches only the
> parts it needs, with shallow clones.

The repository pins the exact versions through its submodules
(`lib/micropython`, `lib/lvgl`, `lib/esp-idf`). You do not need to check out
any tags yourself.

---

## 3. Build

Run this from the repository root:

```sh
python3 make.py esp32 clean BOARD="ESP32_GENERIC_S3" BOARD_VARIANT="SPIRAM_OCT" \
    --flash-size="16" --ota \
    --partition-size="4194304" --skip-partition-resize \
    DISPLAY="st7789" INDEV="ft6x36"
```

### What each argument means

| Argument | Meaning |
|---|---|
| `esp32` | Build target. Must come first. |
| `clean` | Delete the previous build before building. Optional, see section 6. |
| `BOARD="ESP32_GENERIC_S3"` | Generic ESP32-S3 module. |
| `BOARD_VARIANT="SPIRAM_OCT"` | The module has **octal** PSRAM (for example N16R8, N8R8). Leave it out for **quad** PSRAM modules (for example N8R2, N4R2). |
| `--flash-size="16"` | Flash size in MB. Must match your module. Allowed: 4, 8, 16, 32, 64, 128. |
| `--ota` | Create two app partitions (`ota_0`, `ota_1`) so you can do over-the-air updates. |
| `--partition-size="4194304"` | Size of each app partition in bytes. 4194304 = 4 MiB = `0x400000`. |
| `--skip-partition-resize` | Keep the partition size you gave. Without it, the builder shrinks or grows the app partition to fit the firmware. |
| `DISPLAY="st7789"` | Freeze the ST7789 display driver into the firmware. |
| `INDEV="ft6x36"` | Freeze the FT6x36 touch driver into the firmware. |

To use different hardware, change `DISPLAY` and `INDEV`. The available names
are the folder names in `api_drivers/common_api_drivers/display/` and the file
names (without `.py`) in `api_drivers/common_api_drivers/indev/`. You can
repeat `DISPLAY=` and `INDEV=` to include more than one driver. The full list
of options is in `README.md`, section *Command line syntax/parameters*.

### What happens on the first run

1. Fetches MicroPython v1.29.0, LVGL v9.6.0 and pycparser into `lib/`.
2. Fetches ESP-IDF v5.5.2 into `lib/esp-idf` and runs its installer. This puts
   the compilers and a Python virtual environment into `~/.espressif/`.
3. Fetches MicroPython's own dependencies (mbedtls, micropython-lib, tinyusb,
   berkeley-db).
4. Generates the Python bindings for LVGL (`lv_mp.c`, about 1.6 MB of C) from
   the LVGL headers and `lib/lv_conf.h`.
5. Compiles everything (about 2,500 files) and links the firmware.
6. Merges bootloader, partition table and app into one file.

### Expected output

A successful build ends with lines like these:

```
micropython.bin binary size 0x25e990 bytes. Smallest app partition is 0x400000 bytes. 0x1a1670 bytes (41%) free.
Project build complete. ...
Wrote 0x27e990 bytes to file .../build/lvgl_micropy_ESP32_GENERIC_S3-SPIRAM_OCT-16.bin, ready to flash to offset 0x0
To flash firmware:
...
```

You will also see **thousands of `#warning ... is deprecated` lines** during
compilation. They come from LVGL 9.6 reporting old `lv_conf.h` option names
(`LV_COLOR_DEPTH`, `LV_ASSERT_HANDLER_INCLUDE` and a few others). They are
harmless.

The firmware file is:

```
build/lvgl_micropy_ESP32_GENERIC_S3-SPIRAM_OCT-16.bin
```

The partition layout this command produces (16 MB flash, OTA, 4 MiB apps):

| Name | Type | Offset | Size |
|---|---|---|---|
| nvs | data | 0x9000 | 0x14000 |
| otadata | data | 0x1D000 | 0x2000 |
| phy_init | data | 0x1F000 | 0x1000 |
| ota_0 | app | 0x20000 | 0x400000 (4 MiB) |
| ota_1 | app | 0x420000 | 0x400000 (4 MiB) |
| vfs | data (FAT) | 0x820000 | 0x7E0000 (~7.9 MiB) |

---

## 4. Flash the board

### Find the serial port

- macOS: `ls /dev/cu.*`. The ESP32-S3's native USB shows up as
  `/dev/cu.usbmodem…`. A USB-UART bridge shows up as `/dev/cu.usbserial…` or
  `/dev/cu.wchusbserial…`.
- Linux: usually `/dev/ttyACM0` (native USB) or `/dev/ttyUSB0` (USB-UART). If
  you get a permission error, add yourself to the `dialout` group
  (`sudo usermod -aG dialout $USER`) and log in again.

### Flash

At the end of the build, `make.py` prints the exact flash command. It looks
like this (the Python path depends on your Python version):

```sh
~/.espressif/python_env/idf5.5_py3.15_env/bin/python -m esptool --chip esp32s3 \
    -p /dev/cu.usbmodem1101 -b 460800 \
    --before default_reset --after hard_reset \
    write_flash --flash_mode dio --flash_size 16MB --flash_freq 80m \
    --erase-all 0x0 build/lvgl_micropy_ESP32_GENERIC_S3-SPIRAM_OCT-16.bin
```

Replace the port with yours.

> **Warning:** `--erase-all` wipes the whole flash, including the filesystem
> and any Python files you stored on the board. Copy them off first, or remove
> `--erase-all` if you only want to replace the firmware. Erasing is
> recommended when you upgrade from an older firmware.

If esptool cannot connect, put the board in download mode: hold **BOOT**,
press and release **RESET**, then release **BOOT**, and run the command again.
After flashing, press **RESET** once.

You can also let `make.py` flash right after building by adding
`deploy PORT=/dev/cu.usbmodem1101` (and optionally `BAUD=921600`) to the build
command.

---

## 5. Check that it works

Open the REPL, for example with `mpremote` (`pip install mpremote`):

```sh
mpremote connect /dev/cu.usbmodem1101 repl
```

Then:

```python
>>> import sys, gc
>>> sys.version
'3.4.0; MicroPython v1.29.0-dirty on 2026-11-15'
>>> import lvgl as lv
>>> lv.version_major(), lv.version_minor(), lv.version_patch()
(9, 6, 0)
>>> gc.mem_free()          # several MB when the PSRAM was detected
```

- **`-dirty` in the version is normal.** The builder patches a few files inside
  `lib/micropython` while it builds.
- **`gc.mem_free()` only around 200 KB** means PSRAM is not being used. Check
  that `BOARD_VARIANT` matches your module (octal or quad PSRAM).

For display and touch setup code (SPI bus, ST7789, FT6x36), see the
*Python code examples* section in `README.md`.

---

## 6. Rebuilding

- **After changing drivers, options or Python files**, run the same command.
  You can drop `clean` for a faster incremental build. The LVGL bindings are
  regenerated on every build.
- **When something looks stale or a build fails for no clear reason**, run with
  `clean`, or delete `lib/micropython/ports/esp32/build-ESP32_GENERIC_S3-SPIRAM_OCT/`.
- **To change LVGL features**, edit `lib/lv_conf.h` and rebuild. Every widget,
  font or library you enable there becomes part of the `lv` module, and every
  one you disable disappears from it. For example, only the
  `LV_FONT_MONTSERRAT_NN` fonts set to `1` exist as `lv.font_montserrat_NN`.
  Each extra font adds flash.

---

## 7. Troubleshooting

| Symptom | What to do |
|---|---|
| `compiling on windows is not supported at this time` | Build on macOS or Linux. |
| A `git submodule` step fails or was interrupted | Run `git submodule update --init --depth=1 -- lib/micropython lib/lvgl lib/pycparser`, then run the build again. For a broken ESP-IDF download, run `git submodule deinit -f lib/esp-idf` and build again so it is fetched fresh. |
| `unable to locate python version used in the ESP-IDF` (after a successful compile) | Your Python is newer than the versions `builder/esp32.py` looks for. Add your version (for example `'3.16'`) to the `for ver in (...)` list in `compile()`. The firmware itself was already built in `lib/micropython/ports/esp32/build-*`. |
| `Error: app partition is too small` | The firmware no longer fits in 4 MiB. Raise `--partition-size` (for example `5242880` for 5 MiB), or leave out `--skip-partition-resize` and `--partition-size` on non-OTA builds so the builder sizes it for you. |
| Thousands of `#warning ... deprecated` lines | Harmless LVGL 9.6 deprecation notices. |
| `AttributeError` on an `lv.*` name at runtime | The feature or font is disabled in `lib/lv_conf.h`, or the function was renamed in LVGL 9.5/9.6. Use `dir(lv)` or `dir(obj)` to find the current name. Old-to-new name mappings are in `lib/lvgl/include/lvgl/api_map/`. |
| Display shows garbage or wrong colours | Check the color byte order and rotation settings of your display driver, and the SPI pins and frequency. |
| You already use another ESP-IDF version (`IDF_PATH` is set) | Usually no action needed: `make.py` uses your `IDF_PATH` only if it reports v5.5.2 (or plain v5.5), and otherwise uses `lib/esp-idf`. To be safe, build from a fresh terminal where you have not run ESP-IDF's `export.sh`. |

---

## 8. For maintainers: what was changed for MicroPython 1.29 / LVGL 9.6

The upgrade from MicroPython 1.27 / LVGL 9.4 / ESP-IDF 5.5.1 needed these
changes:

1. **Submodule pins**: `lib/micropython` → v1.29.0
   (`0fd6c573ea815774668bbb16b8e197c8822368b2`), `lib/lvgl` → v9.6.0
   (`80ca777e37a2b176770726a02e07a6fb79ef0b39`), `lib/esp-idf` → v5.5.2
   (`30aaf64524299d3bde422ca9a2848090d1bc5d0f`).
2. **`builder/esp32.py`**: `IDF_VER = '5.5.2'`, Python 3.15 added to the list
   of ESP-IDF Python environments, updated version messages.
   **`builder/__init__.py`**: updated version messages.
3. **`gen/python_api_gen_mpy.py` and `gen/lvgl_api_gen_mpy.py`**: MicroPython
   1.29 removed `mp_obj_int_to_bytes_impl()`. The generated code now calls
   `mp_obj_int_to_bytes(obj, sizeof(val), (byte*)&val, big_endian, false, false)`.
4. **`gen/fixed_gen_json.py`**: LVGL's `scripts/gen_json/pycparser_monkeypatch.py`
   crashes on negative enum values (`LV_COORD_MIN`, new in 9.6) because it
   formats them with `hex(value)[2:]`. `fixed_gen_json.py` now shadows `hex()`
   in that module with a 32-bit two's complement version, so the LVGL
   submodule stays untouched.
5. **`api_drivers/py_api_drivers/frozen/display/display_driver_framework.py`**:
   `delete_event()` calls `remove_event()`, because LVGL 9.5 renamed
   `lv_display_delete_event`.

### Moving to newer versions later

1. Look up the commit of the new tag, for example:
   `git ls-remote https://github.com/micropython/micropython.git 'refs/tags/v1.30.0^{}'`
2. Point the submodule at it:
   `git update-index --cacheinfo 160000,<commit>,lib/micropython`
   (same for `lib/lvgl` and `lib/esp-idf`), then
   `git submodule update --init --depth=1 -- lib/micropython lib/lvgl`.
3. Check which ESP-IDF version the new MicroPython recommends in
   `lib/micropython/ports/esp32/README.md` and update `IDF_VER` in
   `builder/esp32.py`.
4. Build with `clean` and fix what breaks. The usual suspects are the binding
   generator in `gen/`, the replacement files in `micropy_updates/esp32/`, and
   the string patches applied by the `update_*()` functions in
   `builder/esp32.py`.

## 9. Build commands
```
python3 make.py esp32 clean BOARD="ESP32_GENERIC_S3" BOARD_VARIANT="SPIRAM_OCT" \
    --flash-size="16" --ota \
    --partition-size="4194304" --skip-partition-resize \
    DISPLAY="st7789" INDEV="ft6x36" 
```
```
DO_CLEAN=1 DO_FLASH=1 DO_ERASE=0 bash /Volumes/ORICO/CSMB/firmware/build.sh
```
