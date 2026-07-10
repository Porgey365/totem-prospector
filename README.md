# ZMK Config for Totem Keyboard + Prospector Dongle

ZMK firmware configuration for the Totem 38-key split keyboard, using a
[Prospector](https://github.com/carrefinho/prospector-zmk-module) dongle
(with display + ambient light sensor) as the BLE split central.

This repo starts fresh (clean git history) from a prior debugging repo,
`zmk-config-test`, which is kept around as reference for what's already been
tried. See [Known Issues](#known-issues) below for open problems.

## Hardware

- **Board**: Seeeduino XIAO BLE (both halves + dongle)
- **Keyboard**: Totem (38 keys)
- **Dongle**: Prospector adapter — display + APDS9960 ambient light sensor,
  acts as the BLE split central
- **Features**:
  - Mouse/pointing support
  - ZMK Studio support (via dongle)
  - Battery level monitoring with RGB LED indicator on each half
    - Uses [zmk-rgbled-widget](https://github.com/caksoylar/zmk-rgbled-widget) with rgbled_adapter
    - Battery voltage: 4.2V (100%) to 3.45V (0%)
  - BT transmit power +8dBm
  - Deep sleep mode on the halves (30 minute idle timeout); dongle stays awake (USB powered)

## Known Issues

### ~~BLE split connection drops constantly~~ (resolved)

Both halves would connect to the dongle and immediately disconnect/reconnect
in a loop, logging `Security failed: ... level 1 err 9` (Zephyr's
`BT_SECURITY_ERR_UNSPECIFIED`) on every attempt.

Ruled out via USB debug logging and hardware testing, in order:

- Stale/mismatched bonds — still failed after a byte-for-byte correct
  `settings_reset` procedure (official ZMK order) on both sides
- Our own BLE config (`CONFIG_ZMK_BLE_EXPERIMENTAL_CONN`,
  `CONFIG_BT_SMP_ALLOW_UNAUTH_OVERWRITE`) — still failed with vanilla ZMK
  security settings
- One bad keyboard half — both halves failed identically against the dongle,
  while pairing fine with each other directly (no dongle)

Root cause: **a bad external 32kHz LF crystal on the dongle board.** The LF
clock governs BLE connection-event timing (separate from the main radio
crystal), so USB worked fine but every BLE link was unstable. Fixed by
forcing the internal RC oscillator instead —
`CONFIG_CLOCK_CONTROL_NRF_K32SRC_RC=y` in `totem_dongle.conf`. This isn't
needed on the halves, whose crystals are fine.

### Ambient light sensor (APDS9960) not working (open, deferred)

The sensor on the dongle isn't producing readings. A boot-time I2C register
probe found an unrecognized chip ID (`0x9f`) that doesn't match any
documented genuine or clone APDS9960 ID. Deferred until the BLE issue above
is resolved.

## Building

Firmware is built automatically via GitHub Actions
(`.github/workflows/build.yml`) on every push, using ZMK's
`build-user-config.yml` reusable workflow and the `build.yaml` matrix.

```
./download-firmware.sh [branch]     # pull the latest successful build
./flash-firmware.sh [dongle|left|right|trackball|reset]
```
