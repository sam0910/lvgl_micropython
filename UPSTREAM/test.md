make instructions on the folder @UPSTREAM, infomations on @UPSTREMA/README.md, if submodule
  lvgl and micropython update to latest version. i need keep my settings on that. copy the
  modified files into that folder, write a instruction on README.md. I've modified lib/lv_conf.h,
  lib/micropython/ports/esp32/boards/sdkconfig.base,lib/micropython/ports/esp32/boards/
  ESP32_GENERIC.S3/mpconfigboard.h,  
  if the build script builder/esp32.py or build.sh change the files, leave it.
  example lib/lvgl/lvgl.h will be modified when running build.sh