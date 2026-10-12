# Corsair Cooling for Omarchy

Omarchy bar widget for Corsair Commander CORE fans, AIO pump and RGB.

![Corsair Cooling panel: Overview, Cooling curve editor and Lighting tabs](preview.png)

A coolant readout in the bar, styled like
[hw-monitor](https://github.com/meviusisback/omarchy-hw-monitor), opens a
tabbed panel:

- **Overview** — coolant, pump and fan dials, coolant history, per-fan RPM.
- **Cooling** — Quiet, Balanced, Performance and Full Speed presets, or drag
  your own fan curve (live coolant marker, dashed line = curve on the
  controller) and set the pump duty. Every write needs a second confirm.
- **Lighting** — effects, theme-synced or custom colours, brightness and speed,
  separately for the pump head and the fans, with a live LED preview.

Keys: `1` `2` `3` switch tabs, `r` refreshes, `Esc` closes.

Curves are stored on the controller and run on coolant temperature. The helper
validates every write: 2–7 points, rising temperatures within 20–60°C, fan duty
never falling and never below 20%, a last point of 100%, pump 50–100%. The
upstream driver labels Commander CORE support as broken/experimental, so watch
the first application of a new curve.

## Install

Requires `liquidctl` 1.16.0 or newer, running on Python 3.11 or newer.
Install it first:

```bash
sudo pacman -S liquidctl
```

If that conflicts with `python-hid` required by QMK, keep QMK intact and use an
isolated install:

```bash
pipx install liquidctl
```

Linux also needs liquidctl's official
[`71-liquidctl.rules`](https://github.com/liquidctl/liquidctl/blob/main/extra/linux/71-liquidctl.rules)
for unprivileged device access. Distribution packages normally install it. For
a `pipx` install, copy the version-matched rule to `/etc/udev/rules.d/`, reload
udev, and trigger both USB and hidraw devices.

Then install the widget:

```bash
omarchy plugin add https://github.com/matteodevenuto/omarchy-corsair-cooling.git --enable
```

## Safety

- Without `corsair-rgbd`, telemetry refresh is manual because every request
  flashes the RGB. Press `r` in the panel or middle-click the bar widget.
- No profile is applied automatically at startup.
- Every fan or pump write requires a second click to confirm.
- USB requests are serialized because Omarchy creates one widget per monitor
  and Commander CORE uses a stateful protocol.
- Curves can never stop the pump or fans and always reach 100% fan duty.

The liquidctl driver currently labels Commander CORE support as
`broken`/experimental. Watch coolant temperature and RPM during the first use
of each profile.

## Stopping the RGB flash: `corsair-rgbd`

Every `liquidctl` request wakes the Commander CORE (software mode, LEDs off) and
then puts it back to sleep (hardware mode, lighting effect restarts). That
mode switch is the flash
([`liquidctl` #448](https://github.com/liquidctl/liquidctl/issues/448)). Firmware
2.x rejects sensor reads in hardware mode, so they cannot avoid the wake.

`corsair-rgbd` keeps the controller in software mode instead. It renders the
lighting itself, re-sends frames as a keepalive (the controller falls back to
hardware mode after about 30 s of silence) and caches telemetry. While it runs,
the widget polls that cache every 5 s, and profile writes skip the sleep, so
nothing flashes. Stopping the daemon restores the iCUE hardware effect.

Fan curves stored on the controller only run in hardware mode, so while the
daemon holds software mode it reads them back from the controller and drives
the pump and fans to the same duty every 3 s. If the daemon stops, the
controller returns to hardware mode within about 30 s and runs the same stored
curves itself.

The daemon is optional and runs as your user; it needs no root. Enable it
once:

```bash
systemctl --user link ~/.config/omarchy/plugins/matteodevenuto.corsair-cooling/corsair-rgbd.service
systemctl --user enable --now corsair-rgbd
```

## Lighting

Needs `corsair-rgbd`. Changes apply instantly and need no confirmation.

- **Static**, **Breathing**, **Wave**, **Spinner** — use the chosen colour; the
  first swatch follows the Omarchy theme accent and changes with the theme.
- **Theme palette** — the theme's red→magenta colours flowing around each ring.
- **Coolant temp** — blue at 30°C through green to red at 45°C.
- **Rainbow**, **Color cycle**, **Off**.

From a script or keybind:

```bash
~/.config/omarchy/plugins/matteodevenuto.corsair-cooling/corsair-cooling lighting all palette theme 100 5
# arguments: ZONE(all|aio|fans) EFFECT theme|RRGGBB BRIGHTNESS(0-100) SPEED(1-10)
qs ipc -p /usr/share/omarchy/shell call matteodevenuto.corsair-cooling lighting fans static ff6000 80 5
qs ipc -p /usr/share/omarchy/shell call matteodevenuto.corsair-cooling openTab lighting
```

Settings live in `~/.config/matteodevenuto-corsair-cooling/`.

## Profiles

- **Quiet** — 75% pump; gradual fan curve reaching 100% at 45°C coolant.
- **Balanced** — 85% pump; reaches 100% at 43°C.
- **Performance** — 100% pump; reaches 100% at 40°C.
- **Full Speed** — pump and all six fans at 100%.
- **Custom** — anything you drag in the curve editor.

## Remove

Stop the daemon first if you enabled it; this restores the hardware lighting:

```bash
systemctl --user disable --now corsair-rgbd
omarchy plugin remove matteodevenuto.corsair-cooling
rm -rf ~/.config/matteodevenuto-corsair-cooling   # optional: lighting and profile settings
```

Removing the widget does not reset a curve already stored on the controller.
Apply the desired profile before removal or power-cycle the controller.
