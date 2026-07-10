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

### BLE split connection drops constantly (open)

Both halves connect to the dongle and then disconnect/reconnect in a loop.
Config currently applies the standard fixes for this class of problem:

- `CONFIG_BT_MAX_CONN` / `CONFIG_BT_MAX_PAIRED` sized for 2 peripherals + 5 BLE
  host profiles on the dongle (central) — see `totem_dongle.conf`
- `CONFIG_BT_SMP_ALLOW_UNAUTH_OVERWRITE=y` so a stale bond on one side can't
  permanently block re-pairing — see `totem.conf`
- USB debug logging enabled on all three devices to capture the actual
  disconnect reason codes

None of these alone has resolved it, so it's still open. Not yet ruled out:
physical/RF causes (USB 3.0 ports and cables are well-known 2.4GHz
interferers for exactly this symptom — try a USB 2.0 hub or an extension
cable to move the dongle away from the host), and bond state getting out of
sync across the three devices after repeated reflashing (all three need
bonds cleared together, not just the dongle, when in doubt).

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
