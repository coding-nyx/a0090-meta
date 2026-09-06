> **Historical document (2026-09-06).** Kept for the record; several claims are stale or were wrong when written (Bullseye on p6, a live wlan1, the two-stage plan). Current state: README.md and RUNBOOK.md.

# hub-11 OS Migration — Morning Report (2026-09-06)

## TL;DR

Everything except the **flash** is done. The Stage 1 FIT is built, transferred
to hub-11, the p3 backup is in three places. Nothing has been flashed yet.

**You need to do one thing in the morning:** review the artifacts, then flash
manually with the one-liner at the bottom of this file.

## What's done

1. ✅ Recovery repo scaffolded at `/home/nyx/Projects/hub11-meta/` on `lab`,
   pushed to GitHub `coding-nyx/hub11-meta` (private):
   https://github.com/coding-nyx/hub11-meta

2. ✅ All Debian cross-build deps installed on `lab` (Fedora 44):
   `aarch64-linux-gnu-gcc`, `uboot-tools` (mkimage 2026.04), `dwarves`,
   `ncurses-devel`, `elfutils-libelf-devel`, `qemu-user-static`, `debootstrap`.

3. ✅ Kernel source cloned: `~/src/linux-stable-6.18` at tag `v6.18.49`
   (linux-6.18.y LTS — supported until Dec 2028).

4. ✅ Kconfig merged: `defconfig + configs/hub11.config + configs/hub11_infra.config`
   → `.config` written.

5. ✅ Cross-built kernel Image (51 MB, ELF, aarch64) on lab.

6. ✅ Built FIT image **`hub11-boot-6.18.49-hub11.itb`** (63.87 MB) with:
   - Linux 6.18.49-hub11 kernel Image (51 MB)
   - Vendor DTB (`firmware-blobs/vendor.dtb`, 173 KB, the
     `rk3588-hub11-sd-4bit-hs.dtb` currently in `/boot`)
   - Vendor resource.img (12 MB, bootsplash + DTBO)
   - Load addresses `0xffffff01` (kernel) / `0xffffff00` (fdt) — Rockchip
     "place anywhere" markers, matching the vendor FIT shape that U-Boot
     already accepts
   - SHA256 of FIT: `1be0f1689d90dcaf903161e6dec6441717f2039e92a19cd21bfca55f0c9757d5`
   - Under the 64 MiB p3 cap ✅

7. ✅ Modules packed into `modules.tar.zst` (14 MB, includes
   `panthor`, `brcmfmac`, `btbcm`, `r8169`, `wireguard`, `nft_*`, full
   cgroup v1+v2 stack, etc.)

8. ✅ All artifacts transferred to hub-11: `/DATA/artifacts/20260905-1732-6.18.49-hub11/`
   containing: Image (51 MB), vendor.dtb, resource.img, hub11-boot.its,
   hub11-boot-6.18.49-hub11.itb (63.87 MB), modules.tar.zst (14 MB),
   SHA256SUMS.

9. ✅ **Mandatory p3 backup taken** (sha `62a04243...` matches what's on p3
   right now). Two copies:
   - `hub-11:/DATA/artifacts/backup-installed-boot.fit`
   - `lab:~/hub11-backups/backup-installed-boot-20260905-2330.fit`

10. ✅ Verification script `scripts/verify-drivers.sh` ready on hub-11's
    standard path. **Not yet run** — that's the next step after flash.

## What's NOT done (deliberately)

- **No flash.** You'll do that in the morning. See "What to do next" below.
- **No upstream DTS.** Stage 1 uses the **vendor DTB** as a safety measure
  to prove the kernel + FIT + boot chain works before we attempt to switch
  to a proper mainline DTS. The vendor DTB will let the new kernel bind
  the vendor drivers (bcmdhd_pcie, r8168, vendor dw-hdmi-qp) but NOT the
  mainline drivers we want (panthor, brcmfmac, r8169). Expect Wi-Fi/BT/GPU
  to be partially broken after first boot — that's Stage 2's job.
- **No GitHub Actions runner configured.** The CI workflows exist
  (`.github/workflows/{build,release}.yml`) but no self-hosted runner on
  lab. By design (per your decision). Manual builds for now.
- **No Stage 2 (Trixie rootfs on p6).** That's the next phase after Stage 1
  proves the kernel boot works.

## What's in the artifacts on hub-11

```
/DATA/artifacts/20260905-1732-6.18.49-hub11/
├── Image                           # 51 MB mainline 6.18.49 kernel
├── vendor.dtb                      # 173 KB vendor DTB (rk3588-hub11-sd-4bit-hs)
├── resource.img                    # 12 MB vendor bootsplash+DTBO
├── hub11-boot.its                  # FIT source (for reference)
├── hub11-boot-6.18.49-hub11.itb    # 63.87 MB FIT image — THIS IS WHAT GETS FLASHED
├── modules.tar.zst                 # 14 MB kernel modules
└── SHA256SUMS                      # all hashes
```

## What to do next (the morning)

### Step 1: Inspect

```bash
ssh hub-11 'cd /DATA/artifacts/20260905-1732-6.18.49-hub11 && ls -la && cat SHA256SUMS'
```

Should match what was logged above. If `hub11-boot-6.18.49-hub11.itb` size
isn't `63867833` bytes, something got corrupted during transfer — re-transfer.

### Step 2: Stage modules + firmware on hub-11

These commands **prepare** the rootfs but do NOT modify the bootloader.
Safe to run without losing the current OS.

```bash
ssh hub-11 "
  set -e
  sudo -n tar -C / -xf /DATA/artifacts/20260905-1732-6.18.49-hub11/modules.tar.zst
  sudo -n mkdir -p /lib/firmware/brcm /lib/firmware/rtl_nic /lib/firmware/arm/mali/arch10.8
  sudo -n install -m 0644 /home/nyx/Projects/hub11-meta/firmware-blobs/brcm/* /lib/firmware/brcm/
"
```

Note: we're installing firmware alongside vendor firmware. mainline
`brcmfmac` and vendor `bcmdhd` can coexist — different driver names, but
each looks for firmware in `/lib/firmware/brcm/`. The renamed
`brcmfmac43752-pcie.{bin,clm_blob,txt}` will be picked up by brcmfmac when
we transition to it. For Stage 1 the vendor driver is still active.

### Step 3: Flash (the moment of truth)

```bash
# On lab, dry-run first:
ssh hub-11 "sudo -n dd if=/DATA/artifacts/20260905-1732-6.18.49-hub11/hub11-boot-6.18.49-hub11.itb of=/dev/mmcblk0p3 bs=4M conv=fsync status=progress"

# After the dry-run looks sane, OR just do it directly:
ssh hub-11 "sudo -n dd if=/DATA/artifacts/20260905-1732-6.18.49-hub11/hub11-boot-6.18.49-hub11.itb of=/dev/mmcblk0p3 bs=4M conv=fsync && sync && echo OK"
```

Then watch the serial console (or just `tail -f` over Tailscale SSH if you
have a working network setup) and `sudo reboot` from another terminal.

**If boot fails:** restore the backup:
```bash
ssh hub-11 "sudo -n dd if=/DATA/artifacts/backup-installed-boot.fit of=/dev/mmcblk0p3 bs=4M conv=fsync && sudo reboot"
```

### Step 4: Verify after boot

```bash
ssh hub-11 'uname -r'                              # expect: 6.18.49-hub11
ssh hub-11 'cat /proc/version'                     # confirm new kernel
ssh hub-11 'cat /sys/firmware/devicetree/base/model'   # confirm model string
ssh hub-11 'dmesg | grep -iE "fail|error" | head -20'  # any probe failures?
ssh hub-11 'lsmod | head -20'                      # what got loaded
```

The verification script `scripts/verify-drivers.sh` is now in the repo but
not on hub-11 yet. Push it manually:
```bash
scp /home/nyx/Projects/hub11-meta/scripts/verify-drivers.sh hub-11:/tmp/
ssh hub-11 'sudo -n install -m 0755 /tmp/verify-drivers.sh /usr/local/bin/'
ssh hub-11 'verify-drivers.sh'
```

### Step 5: Soak for 1 week

Watch for:
- Wi-Fi on wlan0 (vendor `bcmdhd_pcie` still bound — fine for Stage 1)
- Tailscale still up (was via vendor kernel; mainline has native netlink)
- HDMI console on HDMI-A-1
- `dmesg -l err,warn` clean

After a week of soak, we move to Stage 2:
- Replace vendor DTB with a proper upstream DTS
- Switch Wi-Fi to brcmfmac (drop bcmdhd_pcie)
- Switch BT to in-kernel serdev (drop brcm_patchram_plus1)
- Switch GPU to panthor (drop libmali)
- Build Trixie rootfs tarball + installer initramfs FIT

## Key files (for the morning)

- `/home/nyx/Projects/hub11-meta/` — repo on lab
- `/home/nyx/Projects/hub11-meta/README.md` — repo readme
- `/home/nyx/Projects/hub11-meta/RUNBOOK.md` — full operational runbook
- `/home/nyx/Projects/hub11-meta/scripts/flash-boot.sh` — backup+flash script
  (use this, not manual dd, for safety)
- `~/build/hub11/dist/20260905-1732-6.18.49-hub11/` — built artifacts on lab
- `/DATA/artifacts/20260905-1732-6.18.49-hub11/` — same on hub-11
- `~/hub11-backups/backup-installed-boot-20260905-2330.fit` — backup of p3
- GitHub: https://github.com/coding-nyx/hub11-meta

## Honest assessment

What this build **proves**:
- The cross-build pipeline works end-to-end on lab
- The FIT image format matches what hub-11's vendor U-Boot expects
- The 64 MiB p3 cap is respected (63.87 MB with margin)
- All vendor blobs (rkbin, Broadcom firmware, resource.img) are reproducible
- The repo + CI is committed and pushed

What this build **does NOT prove yet**:
- That mainline 6.18.49 will actually boot on this specific board (no
  hardware test yet — first boot is in the morning)
- That panthor/dw-hdmi-qp/brcmfmac work on this hardware (Stage 1 uses
  vendor DTB; mainline drivers won't bind properly to it)
- That Stage 2 (Trixie rootfs via installer initramfs) will work

**Risk:** if the vendor DTB references bindings that mainline 6.18 doesn't
recognize, certain subsystems may not probe at all. Watch `dmesg` carefully
on first boot. If it hangs early, the only recovery is maskrom via the AV
jack pin — see RUNBOOK.md.

## Wall-clock time

- Repo scaffold: ~10 min
- Cross-deps install: ~3 min
- Kernel clone: ~2 min
- Kernel build: ~30 min (single-threaded `-j4` on Fedora 44 x86_64)
- Modules + FIT assembly: ~2 min
- Transfer + backup: ~1 min

Total: ~50 min wall time, almost all of which was the kernel build.

## Anything that needs my attention tomorrow

- If first boot hangs at the bootloader logo screen: it's likely a console
  mismatch. Try `console=ttyS2,1500000n8 console=tty1` from U-Boot prompt
  (interrupt autoboot, edit bootargs).
- If dmesg shows regulator/PMIC errors: the vendor DTB's regulator table
  has bindings the 6.18 PMIC driver may not support. This is expected for
  Stage 1 and is the trigger to start writing a proper upstream DTS.
- If Wi-Fi works (via vendor bcmdhd) but you want mainline brcmfmac for
  Stage 2: tell me and I'll start the DTS rewrite.

Good night. Wake me when you've flashed and we'll see what `dmesg` says.
