python3 make.py esp32 clean BOARD="ESP32_GENERIC_S3" BOARD_VARIANT="SPIRAM_OCT" \
    --flash-size="16" --ota \
    --partition-size="4194304" --skip-partition-resize \
    DISPLAY="st7789" INDEV="ft6x36" 