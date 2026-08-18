# uniwill-laptop-mr

Mechanical Revolution (Mechrevo / 机械革命) fork of the Uniwill laptop kernel driver.
Forked to run alongside the mainline `uniwill-laptop` without module-name clashes.

Mainline upstream: https://github.com/Wer-Wolf/uniwill-laptop
(kernel wiki docs: https://docs.kernel.org/next/wmi/devices/uniwill-laptop.html)

## Differences vs upstream

- Module renamed: `uniwill-laptop.ko` -> **`uniwill-laptop-mr.ko`**
  (load with `modprobe uniwill-laptop-mr` / `insmod uniwill-laptop-mr.ko`)
- Driver names: `uniwill_acpi_mr` / `uniwill-wmi-mr` (avoid clashing with mainline)
- Added DMI entry for Mechrevo (Uniwill ODM) machines
  - Verified on-device (2026-08): vendor `MECHREVO` + board `JIAOLONG Series-X6xR55xK`
    (`dmidecode`/sysfs: sys_vendor=MECHREVO, product=JIAOLONG Series, BIOS AMI N.1.40MRO56)
  - Exact match (vendor + board) so other Mechrevo models need their own entry
- Default Mechrevo descriptor enables only HWMON + BATTERY features;
  FN_LOCK/TOUCHPAD/LIGHTBAR to be enabled per-device after on-device verification
- WMI GUID / ACPI ID unchanged (`ABBC0F72-...` / `INOU0000`) — hardware matching untouched

## Build & install

```sh
make
sudo modprobe uniwill-laptop-mr        # DMI entry matches this machine now
# if your machine is not in the table yet: sudo modprobe uniwill-laptop-mr force=1
```

Needs a recent kernel (>= 6.10) with headers installed; build out-of-tree with the
standalone Makefile (this repo).

## MR fork features: performance mode (EC 0x751)

`platform_profile` (kernel ABI, picked up by GNOME/KDE power-profiles-daemon):

```
/sys/class/platform-profile/uniwill_acpi_mr/platform_profile   # or legacy /sys/firmware/acpi/platform_profile
```

| profile  | EC 0x751 | meaning |
|----------|----------|---------|
| quiet    | `0xA0`   | 办公 (office) |
| balanced | `0x00`   | 均衡 (balanced) |
| perform. | `0x10`   | 狂暴 (turbo) |
| custom   | (0x00)   | 自定义（0x726 bit7 + 0x727 bit6 灯 + 0x7C6 bit2 表控，0x751 不变）|

- Reading decodes the current EC state; when the custom flag (0x726 bit7) is
  set the profile reads back as `custom` (measured 2026-08, REPORT 4.6.1).
- Fan boost bit (`0x40`) is an overlay: preserved on both reads and writes when
  switching profiles (measured 2026-08).
- On battery the hotkey never enters `performance` or `custom` (same as Windows).

Silent turbo sub-mode (EC 0x728 bit0, fan capped at 80% in turbo; needs the
console online bit which the driver sets itself):

```
/sys/bus/platform/devices/INOU0000:00/silent_boost     # 0/1, read-write
```

Custom-mode primitives (the fan tables themselves are written by the userspace
daemon; the driver only exposes the EC registers):

```
/sys/bus/platform/devices/INOU0000:00/power_limits    # "SPL SPPT FPPT" watts -> EC 0x783/784/785 (PL1>=75 also sets VRM 65/120)
/sys/bus/platform/devices/INOU0000:00/tcc_offset      # TCC target temp in °C, 0..127 (bit7=enable) -> EC 0x786; write 0 to disable
```

Performance hotkey (WMI event `0xB0`, the physical key next to the power button):

- The driver cycles the profile itself (`quiet -> balanced -> performance`)
  and emits `KEY_F14` for userspace OSDs.
- With `cycle_custom=1` the cycle becomes `quiet -> balanced -> performance ->
  custom` (OEM order: 办公→均衡→狂暴→自定义). It starts disabled because the
  userspace daemon must write the fan tables first:
  ```
  sudo modprobe uniwill-laptop-mr cycle_custom=1     # or echo 1 > /sys/module/uniwill_laptop_mr/parameters/cycle_custom
  ```
- Disable in-driver cycling entirely with `modprobe uniwill-laptop-mr perf_key_auto=0`;
  then only `KEY_F14` is emitted and userspace is expected to write the profile.
- On battery: cycle is limited to `quiet <-> balanced`; `perf_on_battery=1`
  also unlocks performance/custom for the hotkey.

## License

GPL-2.0-or-later, copyright (C) 2025 Armin Wolf. Based on qc71_laptop and tuxedo-drivers.