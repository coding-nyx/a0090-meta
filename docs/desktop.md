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
