# Building LVGL v9.6 into MicroPython v1.29

Source: [A guide for integrating LVGL v9.6 as a module in MicroPython v1.29](https://forum.lvgl.io/t/a-guide-for-integrating-lvgl-v9-6-as-a-module-in-micropython-v1-29/24494)
(jgpeiro, LVGL forum, 2026-11-14). The thread also has an example project
attachment, `esp32_s3_amoled_18.zip`.

> **Note:** this procedure uses the official
> [lv_binding_micropython](https://github.com/lvgl/lv_binding_micropython) as a
> MicroPython user C module, built with MicroPython's own `make`. It does not use
> this repository's `make.py` builder or its `lib/` submodules. Do the work in a
> separate directory.

The procedure was used for the Waveshare ESP32-S3-Touch-AMOLED-1.8 firmware. It
works for any ESP32 board, and for the unix port (a desktop LVGL build for
testing). The result is `import lvgl as lv` on the board, with the full LVGL API
auto-generated from the C headers and compiled in alongside your own C driver
modules.

| Component | Version |
|---|---|
| MicroPython | v1.29.0 |
| LVGL | v9.6.0 |
| lv_binding_micropython | `master` @ `032dda4b7e8419702a4b9c4c8748a4d85d51be61` |
| ESP-IDF | v5.5.2 (the version MicroPython 1.29 expects) |

---

## 1. How it works

```
lvgl/                       LVGL C sources (v9.6.0)
lv_binding_micropython/
 ├─ gen/gen_mpy.py          parses LVGL headers with pycparser, generates lv_mp.c
 ├─ micropython.cmake       USER_C_MODULES entry for CMake ports (esp32, rp2)
 ├─ micropython.mk          USER_C_MODULES entry for Make ports (unix, stm32)
 └─ lvgl -> ../lvgl         LVGL source tree (submodule, or a symlink to your checkout)
lv_conf.h                   your LVGL configuration (passed through LV_CONF_PATH)
```

At build time the binding:

1. Runs the C preprocessor over `lvgl.h`, using your `lv_conf.h`.
2. Parses the result with pycparser and generates `lv_mp.c`, which defines the
   `lvgl` module: every function, struct, enum and callback.
3. Compiles LVGL plus `lv_mp.c` into the firmware.
4. Routes LVGL's allocator to the MicroPython GC heap (`LV_STDLIB_MICROPYTHON`),
   so LVGL objects live in the same heap as Python objects (PSRAM on the S3).

LVGL has no display driver here. You provide a flush callback (Python, C or
both) and an input-device read callback.

---

## 2. Get the sources

```sh
mkdir work && cd work

git clone --depth 1 -b v5.5.2 --recursive --shallow-submodules https://github.com/espressif/esp-idf.git
git clone --depth 1 -b v1.29.0 https://github.com/micropython/micropython.git
git clone --depth 1 -b v9.6.0  https://github.com/lvgl/lvgl.git
git clone https://github.com/lvgl/lv_binding_micropython.git

cd lv_binding_micropython
git checkout 032dda4b7e8419702a4b9c4c8748a4d85d51be61
git submodule update --init pycparser        # required by the generator
rm -rf lvgl && ln -s ../lvgl lvgl            # use exactly LVGL v9.6.0
cd ..
```

> To find which IDF version a MicroPython release needs, check
> `micropython/ports/esp32/README.md`. For v1.29 it is ESP-IDF v5.5.2.

Install the toolchain and fetch MicroPython's dependencies:

```sh
./esp-idf/install.sh esp32s3
. ./esp-idf/export.sh

make -C micropython/mpy-cross -j
make -C micropython/ports/esp32 BOARD=ESP32_GENERIC_S3 submodules   # berkeley-db, micropython-lib, ...
```

---

## 3. Patch the binding for MicroPython 1.29

Both patches are required. Without them the build fails.

### 3.1 `mp_obj_int_to_bytes_impl` no longer exists

MicroPython 1.29 removed this internal function. The generator still emits a
call to it, which fails with an implicit declaration error on the GCC in IDF 5.5.

In `lv_binding_micropython/gen/gen_mpy.py`, replace:

```c
mp_obj_int_to_bytes_impl(obj, big_endian, sizeof(val), (byte*)&val);
```

with:

```c
mp_obj_int_to_bytes(obj, sizeof(val), (byte*)&val, big_endian, false, false);
```

### 3.2 Generated `lv_mp.c` is emptied on every CMake reconfigure

`lv_binding_micropython/micropython.cmake` contains `file(WRITE ${LV_MP} "")`.
Every reconfigure truncates the generated file to 0 bytes. Ninja then treats the
empty file as up to date and never regenerates it, and the link fails with:

```
undefined reference to `mp_module_lvgl'
undefined reference to `mp_lv_roots'
```

Guard it so the file is only created when missing:

```cmake
if(NOT EXISTS ${LV_MP})
    file(WRITE ${LV_MP} "")
endif()
```

If you already hit this, delete `build-<BOARD>/lv_mp.c` and rebuild.

---

## 4. Write `lv_conf.h`

Start from the binding's `lv_conf.h`. It is written for v9.3, but missing options
fall back to the defaults in `lv_conf_internal.h`, so it works with 9.6. Keep
these binding-specific settings:

```c
#define LV_COLOR_DEPTH          16
#define LV_USE_STDLIB_MALLOC    LV_STDLIB_MICROPYTHON   // LVGL allocations go to the GC heap
#define LV_USE_STDLIB_STRING    LV_STDLIB_BUILTIN
#define LV_USE_STDLIB_SPRINTF   LV_STDLIB_BUILTIN
#define LV_USE_OS               LV_OS_NONE              // single-threaded; drive it from asyncio
```

Then tune it for your project. The guide's changes:

```c
#define LV_DEF_REFR_PERIOD      15      // ~60 Hz refresh ceiling (default 33)
#define LV_FONT_MONTSERRAT_12   1       // only enabled fonts exist as lv.font_montserrat_NN
#define LV_FONT_MONTSERRAT_16   1
#define LV_FONT_MONTSERRAT_20   1
#define LV_FONT_MONTSERRAT_24   1
#define LV_FONT_MONTSERRAT_28   1
#define LV_FONT_MONTSERRAT_36   1
#define LV_FONT_MONTSERRAT_48   1
#define LV_USE_SYSMON           1       // + LV_USE_PERF_MONITOR for the FPS/CPU overlay
```

Keep it outside the binding tree, for example `usermods/lv_conf.h`, and point
`LV_CONF_PATH` at it.

> Every widget or feature you enable becomes part of the generated API, and every
> one you disable vanishes from `lv`. For example, `lv.qrcode` only exists with
> `LV_USE_QRCODE 1`. Each enabled font adds 10–100 KB of flash.

---

## 5. ESP32 port (CMake): build as a user C module

### 5.1 Top-level `USER_C_MODULES` file

`USER_C_MODULES` takes one CMake file. Create `usermods/micropython.cmake` to set
the config path and include the binding plus any modules of your own:

```cmake
# usermods/micropython.cmake
set(LV_CONF_PATH ${CMAKE_CURRENT_LIST_DIR}/lv_conf.h)
include(/abs/path/to/lv_binding_micropython/micropython.cmake)

# your own C modules (display transport, etc.)
include(${CMAKE_CURRENT_LIST_DIR}/qspilcd/micropython.cmake)
```

A minimal module of your own:

```cmake
# usermods/qspilcd/micropython.cmake
add_library(usermod_qspilcd INTERFACE)
target_sources(usermod_qspilcd INTERFACE ${CMAKE_CURRENT_LIST_DIR}/qspilcd.c)
target_include_directories(usermod_qspilcd INTERFACE ${CMAKE_CURRENT_LIST_DIR})
target_link_libraries(usermod INTERFACE usermod_qspilcd)
```

Your C module can `#include "lvgl/lvgl.h"` and call LVGL directly. The binding
directory is already on the include path, and `LV_CONF_PATH` is already defined.

### 5.2 Extra ESP-IDF components (gotcha)

If your C module uses an IDF component MicroPython does not already require,
such as `esp_lcd`, adding it from your usermod cmake does nothing. IDF resolves
component dependencies in an early pass that skips `USER_C_MODULES`, so the build
fails with `esp_lcd_panel_io.h: No such file or directory`.

Fix: add the component to the port's list in
`micropython/ports/esp32/esp32_common.cmake`:

```cmake
list(APPEND IDF_COMPONENTS
    ...
    esp_event
    esp_hw_support
    esp_lcd            # added
    esp_driver_spi     # added
    ...
)
```

### 5.3 Board definition

The firmware with LVGL is about 3 MB, which does not fit the default app
partition. Use a custom board with a larger partition:

```
micropython/ports/esp32/boards/MY_BOARD/
 ├─ mpconfigboard.cmake
 ├─ mpconfigboard.h
 ├─ sdkconfig.board
 ├─ partitions-16MiB.csv
 └─ manifest.py           (optional: freeze your Python drivers/apps)
```

`mpconfigboard.cmake`:

```cmake
set(IDF_TARGET esp32s3)
set(SDKCONFIG_DEFAULTS
    boards/sdkconfig.base
    boards/sdkconfig.ble
    boards/sdkconfig.240mhz
    boards/sdkconfig.spiram_quad     # REQUIRED before spiram_oct (it enables SPIRAM itself)
    boards/sdkconfig.spiram_oct
    boards/sdkconfig.flash_qio_80m
    ${MICROPY_BOARD_DIR}/sdkconfig.board
)
set(MICROPY_FROZEN_MANIFEST ${MICROPY_BOARD_DIR}/manifest.py)
```

> **Gotcha:** `sdkconfig.spiram_oct` only switches the PSRAM mode. If you leave
> out `sdkconfig.spiram_quad`, `CONFIG_SPIRAM` is never enabled and you silently
> get no PSRAM. After building, check with
> `grep CONFIG_SPIRAM build-MY_BOARD/sdkconfig`.

`sdkconfig.board`:

```
CONFIG_ESPTOOLPY_FLASHSIZE_16MB=y
CONFIG_PARTITION_TABLE_CUSTOM=y
CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="boards/MY_BOARD/partitions-16MiB.csv"
CONFIG_SPIRAM_SPEED_80M=y
# keep internal RAM free for DMA buffers (LVGL draw buffers, SPI, I2S)
CONFIG_SPIRAM_MALLOC_ALWAYSINTERNAL=4096
CONFIG_SPIRAM_MALLOC_RESERVE_INTERNAL=65536
```

`partitions-16MiB.csv` (5 MB app, about 11 MB filesystem):

```
# Name,   Type, SubType, Offset,   Size
nvs,      data, nvs,     0x9000,   0x6000,
phy_init, data, phy,     0xf000,   0x1000,
factory,  app,  factory, 0x10000,  0x500000,
vfs,      data, fat,     0x510000, 0xAF0000,
```

### 5.4 Build and flash

```sh
cd micropython/ports/esp32
make BOARD=MY_BOARD USER_C_MODULES=/abs/path/usermods/micropython.cmake -j$(nproc)
```

On macOS there is no `nproc`; use `-j$(sysctl -n hw.ncpu)`.

The first build runs `LV_BINDINGS GEN MPY`, which parses LVGL with pycparser.
That step takes several minutes, and the whole build takes 15–25 minutes on 2
cores. Incremental builds after Python-only changes take about 1 minute.

Flash the combined image at offset 0 (replace `COM5` with your port, e.g.
`/dev/cu.usbmodem*` on macOS):

```sh
python -m esptool --chip esp32s3 -p COM5 erase_flash
python -m esptool --chip esp32s3 -p COM5 -b 921600 write_flash -z 0x0 build-MY_BOARD/firmware.bin
```

### 5.5 Offline / restricted networks (optional)

The esp32 port pulls `espressif/mdns` and `espressif/tinyusb` from the Espressif
component registry. If it is unreachable, vendor both from GitHub and point
`ports/esp32/main/idf_component.yml` at them with `path:` dependencies.

The directory names must be `espressif__mdns` and `espressif__tinyusb`, because
the port refers to `espressif__tinyusb` by name. Delete `dependencies.lock*`
afterwards.

---

## 6. Unix port: desktop LVGL for testing

Lets you run and screenshot your real UI code headlessly, without hardware.

```sh
mkdir -p unixmods && ln -s /abs/path/lv_binding_micropython unixmods/lv_binding_micropython
cd micropython/ports/unix
make submodules
make -j USER_C_MODULES=/abs/path/unixmods \
        LV_CONF_PATH=/abs/path/usermods/lv_conf.h \
        FROZEN_MANIFEST=
```

Make ports take a *directory* whose subdirectories each contain a
`micropython.mk`, which is why the binding is symlinked into `unixmods/`. With
`FROZEN_MANIFEST=` empty, asyncio is not frozen, so run with
`MICROPYPATH=.:/path/to/micropython/extmod`.

For screenshots, render into a Python framebuffer in the flush callback and dump
it as raw RGB565.

---

## 7. Runtime glue: display, touch, tick, timer loop

LVGL 9 needs four things from you: a display with draw buffers and a flush
callback, an input device, a millisecond tick, and a regular call to
`lv.timer_handler()`.

```python
import asyncio, time
import lvgl as lv

W, H = 368, 448
lv.init()

disp = lv.display_create(W, H)
disp.set_color_format(lv.COLOR_FORMAT.RGB565)

# Two partial buffers (40 lines). Any buffer-protocol object works: bytearray,
# or a memoryview over DMA-capable RAM allocated by your C module.
size = W * 40 * 2
buf1 = bytearray(size)
buf2 = bytearray(size)
disp.set_buffers(buf1, buf2, size, lv.DISPLAY_RENDER_MODE.PARTIAL)

def flush(disp, area, px_map):
    n = (area.x2 - area.x1 + 1) * (area.y2 - area.y1 + 1) * 2
    pixels = px_map.__dereference__(n)        # zero-copy, writable memoryview
    panel.blit(area.x1, area.y1, area.x2, area.y2, pixels)   # your driver
    disp.flush_ready()
disp.set_flush_cb(flush)

# Optional: controllers that need even-aligned windows (e.g. SH8601)
def rounder(e):
    a = e.get_invalidated_area()
    a.x1 &= ~1; a.y1 &= ~1; a.x2 |= 1; a.y2 |= 1
disp.add_event_cb(rounder, lv.EVENT.INVALIDATE_AREA, None)

# Touch
last = [0, 0]
def read(indev, data):
    p = touch.read()                         # your driver: (x, y) or None
    if p:
        last[:] = p
        data.state = lv.INDEV_STATE.PRESSED
    else:
        data.state = lv.INDEV_STATE.RELEASED
    data.point.x, data.point.y = last
indev = lv.indev_create()
indev.set_type(lv.INDEV_TYPE.POINTER)
indev.set_read_cb(read)

# Tick + timer loop as an asyncio task
async def lvgl_task():
    t = time.ticks_ms()
    while True:
        now = time.ticks_ms()
        lv.tick_inc(time.ticks_diff(now, t)); t = now
        lv.timer_handler()
        await asyncio.sleep_ms(5)
```

Notes:

- **`px_map` type:** in this binding version `px_map` is a `C_Array`.
  `memoryview(px_map)` does *not* give you the pixels. Use
  `px_map.__dereference__(nbytes)`.
- **Tick from C:** a more accurate tick comes from one C call to
  `lv_tick_set_cb(cb)`, where `cb` returns `esp_timer_get_time() / 1000`. Then
  drop `lv.tick_inc`.
- **Fast flush with DMA:** start the transfer and call `flush_ready()`
  immediately. Have the driver wait for the *previous* transfer before starting
  the next. With two buffers LVGL alternates between them, so the buffer being
  transmitted is never the one being rendered.
- **Byte order:** SPI/QSPI panels usually want big-endian RGB565, so swap the
  bytes in place in your C transfer function before the DMA starts.
- **Theme:** `th = lv.theme_default_init(disp, primary, secondary, dark, font)`,
  then `disp.set_theme(th)`.

---

## 8. API notes for v9.6 through this binding

The Python API mirrors the C API: `lv_<class>_<method>(obj, …)` becomes
`obj.<method>(…)`, and `LV_ENUM_VALUE` becomes `lv.ENUM.VALUE`. Check with
`dir()` when unsure.

| What you might try | Correct in 9.6 |
|---|---|
| `chart.set_range(axis, a, b)` | `chart.set_axis_range(axis, a, b)` |
| `lv.calendar_header_arrow(cal)` | `cal.add_header_arrow()` |
| `anim.set_playback_time(ms)` | `anim.set_reverse_duration(ms)` |
| `anim.set_ready_cb(cb)` | `anim.set_completed_cb(cb)` |
| `lv.scr_load_anim(...)` | `lv.screen_load_anim(scr, lv.SCREEN_LOAD_ANIM.MOVE_LEFT, ms, delay, auto_del)` |
| `lv.font_montserrat_18` | only fonts enabled in `lv_conf.h` exist |
| image from raw bytes | `lv.image_dsc_t({"header": {"magic": lv.IMAGE_HEADER_MAGIC, "cf": lv.COLOR_FORMAT.ARGB8888, "w": w, "h": h, "stride": w*4}, "data_size": len(buf), "data": buf})`. Keep a reference to `buf`: LVGL stores only the pointer. |

`lv.obj` is clickable by default. Plain containers used as decoration swallow
presses unless you call `obj.remove_flag(lv.obj.FLAG.CLICKABLE)`.

---

## 9. Verify the build

```sh
# the modules are linked
xtensa-esp32s3-elf-nm build-MY_BOARD/micropython.elf | grep -E " mp_module_lvgl| mp_lv_roots"

# the generated binding is not empty
ls -la build-MY_BOARD/lv_mp.c

# PSRAM and flash size took effect
grep -E "CONFIG_SPIRAM=|CONFIG_SPIRAM_MODE_OCT|CONFIG_ESPTOOLPY_FLASHSIZE=" build-MY_BOARD/sdkconfig
```

On the device:

```python
>>> import lvgl as lv, gc
>>> lv.version_major(), lv.version_minor(), lv.version_patch()
(9, 6, 0)
>>> gc.mem_free()          # ~8 MB with octal PSRAM
```

### Optional: test the real firmware in QEMU

Espressif's QEMU (`python esp-idf/tools/idf_tools.py install qemu-xtensa`) can
boot the ESP32-S3 image, but needs a test variant of the board with four
workarounds:

- **REPL on UART0:** QEMU has no native USB, so set
  `MICROPY_HW_ENABLE_UART_REPL 1`.
- **Quad PSRAM:** QEMU does not emulate octal PSRAM, so drop
  `sdkconfig.spiram_oct`.
- **ADC calibration:** an IDF startup constructor waits forever on hardware QEMU
  does not emulate. Start QEMU with `-s -S` and in GDB run
  `break adc_hw_calibration`, `continue`, `return`, `detach`.
- **Console input:** start QEMU with `-echr 20` so Ctrl-A reaches the raw REPL
  instead of QEMU's console. Send input one character at a time; bulk writes
  overflow the emulated UART.

---

## 10. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `undefined reference to mp_module_lvgl` / `mp_lv_roots` | `lv_mp.c` was emptied on reconfigure. Apply patch 3.2, delete `lv_mp.c`, rebuild. |
| `implicit declaration of mp_obj_int_to_bytes_impl` | Apply patch 3.1. |
| `fake_libc_include` / pycparser errors during GEN MPY | Run `git submodule update --init pycparser` in the binding. |
| `<component>.h: No such file` from your C module | Add the IDF component to `IDF_COMPONENTS` in `esp32_common.cmake` (5.2). |
| App partition too small | Custom partition table with an app partition of at least 4 MB (5.3). |
| `gc.mem_free()` only ~200 KB, LVGL out of memory | PSRAM not enabled. Include `sdkconfig.spiram_quad` before `spiram_oct`. |
| Display shows garbage or wrong colours | Byte order (swap RGB565), wrong COLMOD, or the panel needs aligned windows (use the rounder). |
| `AttributeError` on an `lv.*` name | Feature or font disabled in `lv_conf.h`, or the name changed in v9 (section 8). |
| Viper function constant fails to compile on ESP32 | Integer constants must fit MicroPython's 30-bit small-int range (use `0x3FFFFFFF`, not `0x7FFFFFFF`). |
