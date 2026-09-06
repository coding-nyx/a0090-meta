# Desktop: lean XFCE profile

Installed only when the `xfce` profile is selected in `scripts/build-rootfs.sh`
(default). Package list: `rootfs/packages-xfce.txt`. Config: `rootfs/overlay/etc/skel/.config/`
(copied into `/home/nyx/.config` by `rootfs/hooks/20-user.sh`).

## Design

Minimalist and dark: one translucent 28 px top panel, no desktop icons, no
launchers, no second panel, no compositor shadows. Flat window buttons, one
workspace. Arc-Dark GTK and xfwm4 theme, Papirus-Dark icons, Inter for UI,
JetBrains Mono for terminals. Wallpaper is a repo-generated 1920x1080 PNG
(`rootfs/overlay/usr/share/backgrounds/hub11/hub11.png`, 9 KB): near-black
gradient, faint grid, one cyan accent line.

Panel plugins, left to right: whisker menu, task list (icons only, grouped),
expanding separator, system tray, PulseAudio, power manager, clock `HH:MM`.

Shortcuts: `Super+Return` terminal, `Super+E` Thunar, `Super+R` / `Alt+F2`
app finder, `Super+Space` menu, `Super+L` lock, `Super+Q` close, `Super+D`
show desktop, `Super+Up/Left/Right` maximize/tile, `Print` screenshot.

## What was removed from the Antigravity install

`xorg`, `xserver-xorg`, `xserver-xorg-video-{all,amdgpu,ati,radeon,nouveau,fbdev}`,
`xserver-xorg-input-all`, `xorg-docs-core`. Panthor is driven by Xorg's
built-in `modesetting` driver, so those packages were dead weight on arm64.

## Login

LightDM with the GTK greeter, autologin for `nyx`
(`/etc/lightdm/lightdm.conf.d/01-autologin.conf`), default target `graphical`.
Headless use: `sudo systemctl set-default multi-user.target` and reboot, or
`sudo systemctl stop lightdm` for the current boot.

## Regenerating the wallpaper

The PNG is produced by a few lines of Pillow (see the 2026-09-06 session
notes); replace the file and keep the path, or point
`xfce4-desktop.xml` (`monitorHDMI-1` and `monitor0` blocks) elsewhere.

## Audio

Cards: `hdmi0` (HDMI out, needs a display with speakers or a headphone jack),
`rockchipes8388` (board speaker connector + 3.5 mm headphone jack), `SPDIF`.
PipeWire + WirePlumber serve PulseAudio clients (Bluetooth A2DP via
`libspa-0.2-bluetooth`; pair devices with the Blueman tray applet). The ES8388
powers up with `Output 1/2 Playback Volume` at 0, so `hub11-audio-defaults.service`
sets them at boot (overlay `usr/local/sbin/hub11-audio-defaults`). Change the
default sink with `pactl set-default-sink <name>` or the panel plugin.

### ES8388 wiring and the two bugs that made it silent / whirring

DTS (`analog-sound`): SoC I2S0 is bit/frame clock master (codec-master mode
hangs the I2S0 TDM controller on this board), `mclk-fs = 256`, MCLK 12.288 MHz
from `I2S0_8CH_MCLKOUT`, format `i2s`. Headphone amp enable GPIO4_A4 and speaker
amp enable GPIO1_D3 are `simple-audio-amplifier` aux devices, headphone detect
GPIO1_C4 (active low). Vendor pin routing (LRCK/SCLK/SDI0/SDO0) is identical.

1. Silence: both analog output volume registers default to 0 (fixed by the boot unit).
2. Whirring: in clock-consumer mode the mainline `es8328` driver left the
   MCLK/LRCK ratio register at 0; `patches/0004-ASoC-es8328-program-MCLK-ratio-in-consumer-mode.patch`
   programs it (0x02 = 256fs) like the vendor driver does. Verify with
   `sudo i2cget -f -y 7 0x11 0x18` during playback -> `0x02`.

Bluetooth: if `bluetoothctl show` says `Powered: no` and power-on fails, check
`rfkill list`; a soft block was the cause once (`rfkill unblock bluetooth`).
