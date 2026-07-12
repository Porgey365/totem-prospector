# ZMK Config for Totem Keyboard + Prospector Dongle

ZMK firmware configuration for the Totem 38-key split keyboard, using a
[Prospector](https://github.com/carrefinho/prospector-zmk-module) dongle
(with display + ambient light sensor) as the BLE split central. Dongle
firmware is our own fork of `prospector-zmk-module`
([Porgey365/prospector-zmk-module@totem-idle-timeout](https://github.com/Porgey365/prospector-zmk-module/tree/totem-idle-timeout)),
which adds a display idle timeout that upstream doesn't have — see
[Known Issues](#known-issues).

This repo starts fresh (clean git history) from a prior debugging repo,
`zmk-config-test`, which is kept around as reference for what was already
tried. See [Known Issues](#known-issues) below for the history of what broke
and how it was fixed — both issues found so far are resolved, and everything
here builds and runs cleanly.

## Hardware

- **Board**: Seeeduino XIAO BLE (both halves + dongle)
- **Keyboard**: Totem (38 keys)
- **Dongle**: Prospector adapter — display + APDS9960 ambient light sensor,
  acts as the BLE split central. Display turns off after
  `CONFIG_PROSPECTOR_IDLE_TIMEOUT_S` (300s) of no keyboard activity
- **Features**:
  - Mouse/pointing support
  - ZMK Studio support (via dongle)
  - Battery level monitoring with RGB LED indicator on each half
    - Uses [zmk-rgbled-widget](https://github.com/caksoylar/zmk-rgbled-widget) with rgbled_adapter
    - Battery voltage: 4.2V (100%) to 3.45V (0%)
  - BT transmit power +8dBm
  - Deep sleep mode on the halves (30 minute idle timeout); dongle stays awake (USB powered)

## Known Issues

All three issues below are resolved; kept here as a record in case any
regresses or the symptoms resurface after a hardware change.

### Display doesn't turn off when idle (resolved, patched ourselves)

Upstream `carrefinho/prospector-zmk-module` has no display idle timeout —
the screen stays lit at whatever ambient-light-adjusted brightness
indefinitely.

Tried [Cornix's `zmk-dongle-screen`](https://github.com/bwshockley/zmk-dongle-screen)
as a drop-in replacement module first, since it advertises an idle timeout.
It fails to build against the LVGL version ZMK's current zephyr pin uses:
two of its widgets (`battery_status.c`, `layer_roller.c`) reference LVGL v8
draw APIs that don't exist anymore (`lv_draw_ctx_t`, and a mismatched
`lv_draw_mask_fade_param_t`/`lv_draw_sw_mask_fade_param_t` pair) — a genuine
upstream bug in that module, not something in our config.

Patched our own fork of `prospector-zmk-module` instead, since it's the
firmware we already know is reliable:
[Porgey365/prospector-zmk-module@totem-idle-timeout](https://github.com/Porgey365/prospector-zmk-module/tree/totem-idle-timeout),
based on the same `feat/new-status-screens` branch `config/west.yml` already
pinned. Adds `CONFIG_PROSPECTOR_IDLE_TIMEOUT_S` (seconds, 0 = disabled;
we set 300 in `totem_dongle.conf`): a new `idle_timeout.c` listens for
`zmk_position_state_changed` (fires on the dongle for peripheral keypresses
too) and, after the timeout, calls into `brightness.c`'s existing
ambient-light fade thread to ramp the backlight to 0 — reusing its fade
logic rather than driving the PWM backlight independently, since that
thread re-asserts brightness from the sensor every ~100ms and would fight
an external writer. Turns back on (fades in) on the next keypress.

Along the way, found and fixed a pre-existing bug in `brightness.c`'s
`bl_fade()` (present upstream too, just never noticed since nothing had
ever asked it to fade to exactly 0 before): the loop writes the PWM value
*before* stepping `current_brightness` towards `target`, so the final step
never actually reaches hardware — confirmed via USB serial logging that
`current_brightness` the variable reached `0` while the backlight stayed
lit at 1% duty cycle (dimmed, not off). Fixed by explicitly committing the
target value once the loop exits.

**Like the zephyr fork below, this is a permanent dependency** —
`config/west.yml` needs to keep pointing at
`Porgey365/prospector-zmk-module@totem-idle-timeout` (or a rebase of it)
indefinitely, since upstream doesn't have this feature.

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

### ~~Ambient light sensor (APDS9960) not working~~ (resolved)

The sensor wasn't producing readings. A boot-time I2C register probe found
chip ID `0x9F` on the ID register — stable across repeated reads, not a bus
error, but a clone/counterfeit APDS9960 with a genuinely different ID than
Zephyr's stock driver's two hardcoded accepted values (`0xAB` genuine,
`0x9C` known clone). No Kconfig escape hatch, and a vendored driver
workaround doesn't work here: Prospector's `brightness.c` hardcodes
`DEVICE_DT_GET_ONE(avago_apds9960)`, so the stock driver has to be the one
that binds to the sensor's devicetree node.

Fixed with a small patched fork of `zmkfirmware/zephyr` (same base commit
`zmk/app/west.yml` already pins, `v4.1.0+zmk-fixes`), pointed to from
`config/west.yml`: [Porgey365/zephyr@totem-apds9960-clone-id](https://github.com/Porgey365/zephyr/tree/totem-apds9960-clone-id).
Two changes to `drivers/sensor/apds9960/`:

- Accept `0x9F` as a third valid chip ID alongside the two stock ones
- Stop treating a NACK'd write to `AICLEAR` (`0xE7`, a write-only
  "clear interrupts" pulse register) as fatal — this clone doesn't
  implement it, but it isn't needed for basic ALS operation. This bit the
  boot-time init *and* every subsequent `sample_fetch` call, so leaving it
  fatal would have meant readings kept failing even after "successful" init

Verified working: brightness now visibly responds to covering/uncovering
the sensor.

**This fork is a permanent dependency, not a temporary workaround** — the
clone chip is soldered to the physical board, so `config/west.yml` needs to
keep pointing at `Porgey365/zephyr@totem-apds9960-clone-id` (or an
equivalent patch) indefinitely. If `zmk/app/west.yml` ever bumps its pinned
`zephyr` revision past `v4.1.0+zmk-fixes`, this fork will need to be rebased
onto the new commit.

## Building

Firmware is built automatically via GitHub Actions
(`.github/workflows/build.yml`) on every push, using ZMK's
`build-user-config.yml` reusable workflow and the `build.yaml` matrix.

```
./download-firmware.sh [branch]     # pull the latest successful build
./flash-firmware.sh [dongle|left|right|trackball|reset]
```
