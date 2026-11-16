# LVGL v9.4 → v9.6: API changes

What changed between **LVGL v9.4.0**, **v9.5.0** (18 Feb 2026) and **v9.6.0**
(16 Sep 2026), with a focus on API changes and what they mean for this
MicroPython build.

Sources:

- LVGL's own docs in `lib/lvgl/docs/src/changelog/`: `CHANGELOG_v9.5.0.mdx`,
  `CHANGELOG.mdx` (9.6) and `migration-v9-6.mdx`.
- A diff of the public headers of v9.4.0, v9.5.0 and v9.6.0.
- `lib/lvgl/lvgl.h` preprocessed the same way `gen/python_api_gen_mpy.py` does
  it, which shows exactly which functions the Python `lvgl` module gets.

## Summary

- **v9.6 is the last v9 release.** Everything marked `LV_DEPRECATED` in 9.6 is
  removed in v10.0.
- **Most 9.6 changes are deprecations.** The old C names still compile.
- **MicroPython is stricter than C.** Some renamed functions are kept only as C
  `#define` aliases, and those **do not exist in Python** (see the next
  section). Code that calls them fails at run time with `AttributeError`.
- **Our build compiles with 2 deprecation warnings** from `lib/lv_conf.h`:
  `LV_COLOR_DEPTH` and `LV_ASSERT_HANDLER_INCLUDE`.

## How C changes reach Python

The binding generator runs the C preprocessor on `lvgl.h`, then reads the
result. This has three effects:

| Kind of change in C | Python |
|---|---|
| Function deprecated with `LV_DEPRECATED(...)` | **Still works.** The attribute is stripped (`gen/fake_libc` defines `__attribute__(x)` as nothing). |
| Function renamed, old name kept as a `#define` in `api_map/lv_api_map_v9_*.h` | **Old name is gone.** Macros leave no symbol behind. Use the new name. |
| Function moved to a private header (`src/`) | **Gone.** The generator reads only the public `lvgl.h`. |

Naming in Python: `lv_obj_set_hidden(obj, True)` becomes `obj.set_hidden(True)`,
`lv_display_remove_event(disp, i)` becomes `disp.remove_event(i)`, and plain
functions become `lv.<name>`, e.g. `lv.draw_rgb565_swap(...)`. Enums become
`lv.<ENUM>.<VALUE>`, e.g. `lv.OBJ_FLAG.HIDDEN`.

## 1. Already broken in MicroPython on 9.6

All of these were checked against the preprocessed `lvgl.h` of v9.6.0.

### Renamed (old name is only a C macro now)

| Removed (Python) | Use instead | Changed in |
|---|---|---|
| `tabview.rename_tab(i, txt)` | `tabview.set_tab_text(i, txt)` | 9.5 |
| `disp.delete_event(i)` | `disp.remove_event(i)` | 9.6 |
| `obj.is_valid()` | `obj.is_in_widget_tree()` | 9.6 |
| `observer.remove()` | `observer.delete()` | 9.6 |
| `subject.copy_string(s)` | `subject.set_string(s)` | 9.6 |
| `lv.draw_sw_rgb565_swap(...)` | `lv.draw_rgb565_swap(...)` | 9.6 |
| `lv.draw_sw_rotate(...)` | `lv.draw_rotate(...)` | 9.6 |
| `lv.draw_sw_i1_to_argb8888(...)` | `lv.draw_i1_to_argb8888(...)` | 9.6 |
| `lv.draw_sw_i1_invert(...)` | `lv.draw_i1_invert(...)` | 9.6 |
| `lv.draw_sw_i1_convert_to_vtiled(...)` | `lv.draw_i1_convert_to_vtiled(...)` | 9.6 |
| `lv.COLOR_FORMAT.NATIVE` / `NATIVE_WITH_ALPHA` | name the format, e.g. `lv.COLOR_FORMAT.RGB565`, or `disp.get_color_format()` | 9.6 |

`api_drivers/.../display_driver_framework.py` already calls `remove_event()`.
That fix was made in commit `ed17edc`.

### Moved to the private API in 9.6 (gone from Python)

| Module | Functions |
|---|---|
| Image cache | `lv.image_cache_drop()`, `image_cache_resize()`, `image_cache_is_enabled()`, `image_header_cache_*()` |
| Containers | `lv_array_*`, `lv_tree_*`, `lv_rb_*`, `lv_lru_*`, `lv_circle_buf_*`, `lv_iter_*`, `lv_cache_*` |
| Structures | `lv_event_list_t`, the SVG module's internal structs |
| Software renderer internals | `lv_draw_sw_init()`, `lv_draw_sw_fill()`, blend/mask/gradient functions, `lv_draw_sw_register_blend_handler()` |
| Other | `lv_indev_scroll_handler()` and the rest of `lv_indev_scroll_*`, `lv_global_default()`, `lv_obj_allocate_spec_attr()`, `lv_draw_buf_save_to_file()`, `lv_font_manager_recycle_*` |

> **Watch out for `lv.image_cache_drop()`.** MicroPython apps often call it to
> free image memory, and it no longer exists. C code can still reach it by
> enabling `LV_USE_PRIVATE_API` or including `lvgl_private.h`, but the Python
> binding only reads the public `lvgl.h`.

### Removed in 9.5

- **The XML UI engine** (`lv_xml_*`, about 130 functions, plus `lv_obj_xml_*`).
  Its development continues outside the LVGL repo.
- **`LV_PROPERTY_TEXTAREA_INSERT_REPLACE`.**
- **Wayland client-side window decorations.** The Wayland driver was rewritten.
  This doesn't affect ESP32.

## 2. Deprecated in 9.6: still works, removed in v10

These still work in Python on 9.6. Move to the new API before going to v10.

### Object flags → one setter/getter per flag (the biggest change)

`add_flag()`, `remove_flag()`, `set_flag()`, `has_flag()` and `has_flag_any()`
are deprecated. Each flag now has its own `set_<flag>(bool)` and `is_<flag>()`:

```python
# Before
obj.add_flag(lv.OBJ_FLAG.HIDDEN)
obj.remove_flag(lv.OBJ_FLAG.CLICKABLE)
if obj.has_flag(lv.OBJ_FLAG.HIDDEN): ...

# After (9.6)
obj.set_hidden(True)
obj.set_clickable(False)
if obj.is_hidden(): ...
```

The flags covered are `hidden`, `clickable`, `click_focusable`, `checkable`,
`scrollable`, `scroll_elastic`, `scroll_momentum`, `scroll_one`,
`scroll_chain_hor/ver`, `scroll_chain` (setter only), `scroll_on_focus`,
`scroll_with_arrow`, `snappable`, `press_lock`, `event_bubble`, `event_trickle`,
`state_trickle`, `gesture_bubble`, `adv_hittest`, `ignore_layout`, `floating`,
`send_draw_task_events`, `overflow_visible`, `flex_in_new_track`,
`radio_button`.

The user flags (`LV_OBJ_FLAG_USER_1`..`4`) become `obj.set_user_flag(bit, en)`
and `obj.get_user_flag(bit)`, with bit 0-3.

States have the same style of API: `set_checked()`, `set_disabled()`,
`set_pressed()`, `set_focused()`, `set_edited()`, `set_hovered()`,
`set_scrolled()`, `set_alt()`, `set_focus_key()`, with matching `is_*()`
getters. The generic `obj.set_state(state, en)` is still there.

LVGL ships a converter for C code: `lib/lvgl/scripts/migration/migrate_obj_flags.py`.
It only rewrites C, so Python code has to be changed by hand.

### Other deprecated `lv_obj` functions

| Deprecated | Use instead | Note |
|---|---|---|
| `obj.find_by_id(id)` | `obj.find_by_name("name")` | needs `LV_USE_OBJ_NAME` (on in our `lv_conf.h`) |
| `obj.style_set_disabled(style, sel, True)` | `obj.set_style_enabled(style, sel, False)` | **the bool is inverted** |
| `obj.style_get_disabled(style, sel)` | `obj.get_style_enabled(style, sel)` | inverted |

### Observer (subjects)

Subjects are now created by LVGL and handled through a pointer:

| Deprecated | Use instead |
|---|---|
| `lv_subject_init_int/float/string/pointer/color/group(&s, ...)` | `s = lv_subject_create(LV_SUBJECT_TYPE_INT)` (or `_FLOAT`, `_STRING`, `_POINTER`, `_COLOR`, `_GROUP`), then `lv_subject_set_int(s, v)` |
| `lv_subject_deinit(&s)` | `lv_subject_delete(s)`. This also frees the subject, so don't use it afterwards. |
| string buffers passed to `init_string` | `lv_subject_set_string_buffer_static(s, buf, prev_buf, size)` |
| group list passed to `init_group` | `lv_subject_set_group_list_static(s, list, n)` |
| `lv_obj_bind_flag_if_eq/not_eq/gt/ge/lt/le` | `lv_obj_bind_bool(obj, subject, lv_obj_set_hidden)` (any per-flag setter works) |
| `lv_obj_bind_state_if_*` | a custom observer: `lv_subject_add_observer_obj(subject, cb, obj, NULL)` |

> **Behavior change:** `lv_subject_create()` starts at a neutral value (`0`,
> `NULL`, black, `""`). Set min/max **before** the first `set_int()`, because
> `set_int()` clamps to them and `init_int()` did not.

### Widgets

| Deprecated | Use instead |
|---|---|
| **`lv_list`** (whole widget) | `lv_obj` with a `LV_FLEX_FLOW_COLUMN` layout (example `lv_example_flex_list`) |
| **`lv_menu`** (whole widget) | pages built from `lv_obj` and a back button (example `lv_example_menu_navigation`) |
| **`lv_win`** (whole widget) | flex column with a header bar and a content area (`lv_example_flex_win`) |
| **`lv_file_explorer`** | table plus the `lv_fs` API (`lv_example_table_file_browser`) |
| **`lv_fragment`** (deprecated in 9.5) | no replacement given |
| **rlottie** | `lv_lottie` widget |
| `spangroup.set_align(a)` | `obj.set_style_text_align(a, lv.PART.MAIN)` |
| `spangroup.set_mode(m)` | set the width: `LV_SIZE_CONTENT` expands, a fixed width wraps |
| `textarea.set_align(a)` | `obj.set_style_text_align(a, lv.PART.MAIN)` |
| `lv_scale_section_set_style(sec, part, st)` | `scale.set_section_style_main/indicator/items(sec, st)` |
| `lv_gltf_set/get_env_brightness()` | see the `lv_gltf` docs |

### Drawing, snapshot, layout

| Deprecated | Use instead |
|---|---|
| `lv_image_buf_set_palette()` | `lv_draw_buf_set_palette()` |
| `lv_image_buf_free()` | `lv_draw_buf_destroy()` |
| `lv_snapshot_free()` | `lv_draw_buf_destroy()` |
| `lv_snapshot_take_to_buf(obj, cf, dsc, buf, size)` | `lv_snapshot_take_to_draw_buf(obj, cf, draw_buf)` |
| `lv_layout_register(cb, user_data)` | `lv_layout_create(callbacks, user_data)` with `lv_layout_callbacks_t` |

### `NULL` as the display argument

Passing `NULL` for "the default display" is deprecated for about 50
`lv_display_*` functions (resolution, rotation, layers, screens, theme, flush
callbacks, buffers, …) and for the `lv_sysmon_*` functions. Pass
`lv_display_get_default()` instead. In Python, call the method on a display
object rather than passing `None`.

## 3. Configuration (`lv_conf.h`)

In 9.6 Kconfig is the single source of truth, and `lv_conf_template.h` is
generated from it. A hand-written `lv_conf.h` is still fully supported. Old
option names still compile with a `#warning` and are removed in v10.

### In our `lib/lv_conf.h`

| Option (in our file) | Status | Change for v10 |
|---|---|---|
| `LV_COLOR_DEPTH MICROPY_COLOR_DEPTH` (16) | **warns** | `LV_COLOR_FORMAT_DEFAULT LV_COLOR_FORMAT_RGB565` (or `RGB565_SWAPPED` to drop byte swapping in the flush) |
| `LV_ASSERT_HANDLER_INCLUDE <stdint.h>` | **warns** | `LV_ASSERT_USE_CUSTOM_INCLUDE 1` + `LV_ASSERT_CUSTOM_INCLUDE` |
| `LV_USE_ASSERT_OBJ 0` | removed from the template | replaced by `LV_USE_CHECK_ARG` / `LV_USE_CHECK_OBJ_CLASSTYPE` / `LV_USE_CHECK_OBJ_VALIDITY` |
| `LV_USE_LIST 1`, `LV_USE_MENU 1` | widgets deprecated | gone in v10 (see section 2) |
| `LV_MEM_POOL_EXPAND_SIZE 0` | removed | set the full size in `LV_MEM_SIZE` |
| `LV_USE_LZ4_EXTERNAL 0`, `LV_USE_THORVG_EXTERNAL 0` | removed | `LV_USE_LZ4` / `LV_USE_THORVG` + `_INTERNAL` |
| `LV_CALENDAR_DEFAULT_DAY_NAMES` / `_MONTH_NAMES` | removed (Calendar is off, so no warning) | `LV_MONDAY_STR` … `LV_DECEMBER_STR` |
| `LV_X11_RENDER_MODE_PARTIAL/DIRECT/FULL` | removed (X11 is off) | `LV_X11_RENDER_MODE LV_DISPLAY_RENDER_MODE_PARTIAL` |
| `LV_LIBINPUT_XKB_KEY_MAP` | removed (libinput is off) | `LV_LIBINPUT_XKB_RULES/MODEL/LAYOUT/VARIANT/OPTIONS` |

`UPSTREAM/APPLY.sh` with LVGL `master` (v10) lists exactly which of these
v10 drops.

### Other configuration changes

- **`LV_CONF_MINIMAL` was removed.** Use `configs/defconfigs/empty.defconfig`.
- **`LV_MEM_SIZE_KILOBYTES` was removed.** Set `LV_MEM_SIZE` in bytes.
- **`LV_DRAW_THREAD_STACKSIZE` was renamed** to `LV_DRAW_THREAD_STACK_SIZE`.
- **The VG-Lite GPU is now one option,** `LV_VG_LITE_GPU`, instead of a
  series/revision pair.
- **SDL, DRM and Wayland need an explicit backend,** set with
  `LV_<DRIVER>_BACKEND` (Wayland uses per-backend switches). The
  `_AUTO_BACKEND` flags are temporary.
- **`LV_USE_PXP` and `LV_USE_G2D` are now no-ops.** Use `LV_USE_DRAW_PXP` and
  `LV_USE_DRAW_G2D`.
- **`LV_ATTRIBUTE_*`, `LV_PROFILER_*` and `LV_EXPORT_CONST_INT` are no longer
  printed in the template.** They are still honored when defined.

## 4. Behavior changes (same API, different result)

- **Argument checking (9.6):** about 2,900 `LV_CHECK_ARG` checks across the
  public API. A bad argument (for example `NULL`) now logs a warning and the
  function returns early, instead of crashing. Assert-on-failure is opt-in
  (`LV_CHECK_ARG_ASSERT_ON_FAIL`).
- **Assertions are off by default (9.6).** Turn them on with `LV_USE_ASSERT`.
- **The object style cache is on by default (9.6).**
- **Faster software renderer (9.6).** The blend and transform paths now work a
  word at a time instead of a pixel at a time. LVGL measured an ESP32-S3-Korvo-1
  frame with layered opacity at **14 ms faster**. No config change is needed.
- **QR codes re-encode on later setters (9.6).** `lv_qrcode_set_size()` and
  `set_quiet_zone()` now re-encode when called after the data. Before, those
  changes were silently dropped. Each QR code also keeps a copy of its data,
  costing `data_len` bytes.
- **Leading spaces after a wrap are skipped (9.5).** A wrapped line no longer
  starts with a space, so label line breaks can differ slightly.
- **Keypad events are sent without a group (9.5).** Before, a keypad indev
  needed an assigned group.

## 5. New APIs

### v9.5

- **Blur and drop shadow style properties.** These are rendered in software, so
  they work without a GPU (expect a CPU cost on ESP32):
  - `set_style_blur_radius`, `_blur_backdrop`, `_blur_quality`
  - `set_style_drop_shadow_radius`, `_color`, `_opa`, `_offset_x`,
    `_offset_y`, `_quality`
- **`LV_STATE_ALT`**, a widget state for simple dark/light switching.
- **Theme API:** `obj.remove_theme()`, `obj.bind_style_prop()`, and full
  theme create/copy/delete.
- **Smooth Bézier chart lines:** `LV_CHART_TYPE_CURVE`. Needs
  `LV_USE_VECTOR_GRAPHICS`, which is off in our config.
- **Radio-button groups:** `LV_OBJ_FLAG_RADIO_BUTTON`.
- **Input:** key remapping with `lv_indev_set_key_remap_cb()`, and
  configurable gesture thresholds (`LV_INDEV_DEF_GESTURE_*`).
- **`lv_layout_create()`**, the replacement for `lv_layout_register()`.
- **Property interface** added to arc, bar, switch, checkbox, LED, line, scale,
  spinbox, spinner, table, tabview, buttonmatrix, span, menu and chart.
- **WebP decoder** (`LV_USE_LIBWEBP`).

### v9.6

- **Per-flag and per-state setters/getters** (section 2), plus new events:
  `LV_EVENT_CHECKED`, `LV_EVENT_UNCHECKED`, and directional gestures
  `LV_EVENT_GESTURE_UP/DOWN/LEFT/RIGHT`.
- **Subject API:** `lv_subject_create()`, `lv_subject_delete()`,
  `lv_obj_bind_bool()`.
- **`label.set_max_lines(n)`** limits a label to `n` lines.
- **`set_style_text_leading_trim`** trims a font's leading, so
  `LV_SIZE_CONTENT` labels and buttons size to the glyphs.
- **`LV_IMAGE_ALIGN_CONTAIN_DOWNSCALE`** fits an image without ever scaling
  it up.
- **QR code:** `lv_qrcode_set_update_mode()`, `lv_qrcode_render()`,
  `lv_qrcode_is_render_valid()`.
- **Translation support** for dropdown and roller.
- **Binary fonts load glyphs on demand.**
- **`LV_COLOR_FORMAT_DEFAULT`** can be `RGB565_SWAPPED`, so LVGL renders
  big-endian RGB565 directly.

## 6. Header layout (v9.6)

- **Public headers moved to `lib/lvgl/include/lvgl/`.** `src/` is now private.
- **`#include "lvgl.h"` still works,** and so does the binding generator.
- **Including a moved `src/...` header directly gives a deprecation warning.**
  It stops working in v10.

## What this means for CSMB

1. **Python code on the board:** search for the names in section 1, above all
   `image_cache_drop`, `rename_tab`, `delete_event`, `is_valid` and
   `draw_sw_*`. These fail now on 9.6.
2. **Before v10:**
   - Replace `add_flag`/`remove_flag`/`has_flag` with `set_<flag>()`/`is_<flag>()`.
   - Stop using `lv.list` and `lv.menu`.
   - Fix the 2 `lv_conf.h` warnings.

   In this repo, `api_drivers/py_api_drivers/frozen/indev/touch_calibration/touch_calibrate.py`
   lines 102-110 use `remove_flag()`. That still works on 9.6.
3. **Optional:** the display driver framework already handles byte order
   itself (`rgb565_byte_swap=` and `color_space=` in
   `display_driver_framework.py`, which calls `set_color_format()`). Rendering
   straight to `RGB565_SWAPPED` could replace the software byte swap. Test it
   before relying on it.
