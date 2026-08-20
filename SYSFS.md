# uniwill-laptop-mr sysfs interface

All attributes live on the platform device node:

```
/sys/bus/platform/devices/INOU0000:00/
```

Reads and writes go straight to EC registers through the kernel regmap.
All switches accept `0`/`1` (also `y`/`n`, `on`/`off` etc., `kstrtobool`).

The register semantics below were reverse-engineered from the OEM
GCUService (JIT-decoded IL + on-device measurements), see
`REPORT_GCUService.md` §4.6.1 in the RE workspace.

---

## Custom mode (MR fork)

Custom mode is the OEM "自定义" profile: the EC runs the fan from the
RamFan1p5 tables (0xF00-0xF5F) instead of its built-in curves. The
full activation chain (measured 2026-08, both Windows A/B and Linux):

```
0x741 bit0  online bit (Set_APExistToEC)   — always set by the driver
0x706 = 0x41  custom master switch (SetCustomModetoEC)  — 0x40 = off
0x726 bit7  custom mode flag
0x727 bit6  custom light + detection bit
0x7C5 bit7  independent CPU/GPU fan control (SetEcFanControlRespective)
0x7C6 bit2  RamFan1p5 table control
```

> Missing either 0x706=0x41 or 0x7C5 bit7 and the EC ignores the fan
> tables entirely (this was the root cause of "table written, fan does
> not follow" — fixed in commit 8bea69a).

### `custom_mode` — enter / leave custom mode

```
cat custom_mode          # 0/1, 1 = custom mode active (0x726 bit7)
echo 1 > custom_mode     # enter: full chain + safe defaults
echo 0 > custom_mode     # leave: clear all five bits, 0x706=0x40
```

`echo 1` applies the built-in **safe defaults** until the userspace
daemon writes its own values:

- power limits `75 85 85` W (PL1/PL2/PL4 -> EC 0x783/0x784/0x785) and,
  because PL1 >= 75 W, the VRM current limits `65/120` (0x753/0x754) —
  only if `power_limits` has not been written yet;
- a mild default fan curve (CPU starts at 50 °C, full speed at 95 °C;
  GPU a few degrees lower) — only if `fan_tables` has not been written
  yet.

Once the daemon writes `power_limits` / `fan_tables`, those values take
over and are kept across further `custom_mode` toggles (tracked with
`data->pl_written` / `data->tables_written`, reset on module load).

`platform_profile` also supports `custom` (same chain), but the legacy
`/sys/firmware/acpi/platform_profile` interface rejects the string with
EINVAL; the class device
`/sys/class/platform-profile/uniwill_acpi_mr/platform_profile` accepts
it. Prefer `custom_mode` for daemon-driven custom profiles.

---

## Performance mode (upstream ABI)

```
/sys/class/platform-profile/uniwill_acpi_mr/platform_profile
```

| profile  | EC 0x751 | meaning |
|----------|----------|---------|
| quiet    | `0xA0`   | 办公 (office) |
| balanced | `0x00`   | 均衡 (balanced) |
| perform. | `0x10`   | 狂暴 (turbo) |
| custom   | (unchanged) | 自定义 (0x726 bit7 flag + tables) |

Fan boost (0x751 bit6) is an overlay, preserved across switches.

---

## Custom-mode primitives

```
power_limits    "SPL SPPT FPPT" watts -> EC 0x783/0x784/0x785
                (PL1 >= 75 also sets VRM 65/120 on 0x753/0x754)
tcc_offset      TCC target temp °C 0..127 -> EC 0x786 = target|0x80
                (write 0 to disable)
fan_sensitivity fan curve step interval ms (100..12700, step 100)
                -> EC 0x787 = (ms/100)|0x80; 0 = disabled
fan_tables      96 decimals: 48 CPU + 48 GPU, each (up down duty)*16
                -> EC 0xF00-0xF5F (duty is raw, 0..200 = %*2)
```

`fan_tables` write sequence (same as OEM `SetFanTable`):

1. enable independent fan control (0x7C5 bit7)
2. clear table control (0x7C6 bit2)
3. zero the 0xF00-0xF5F region
4. write both tables
5. set table control (0x7C6 bit2)

> The last three bytes of the GPU duty window (0xF5D-0xF5F) are OEM
> `RamFan1p5` status/control registers, **not** duty slots — keep them 0.

Quick tests:

```sh
# fan at 100% (temp >= 30°C)
python3 -c "print(' '.join(['30 20 200']*32))" | sudo tee .../fan_tables
# fan off (0%)
python3 -c "print(' '.join(['30 20 0']*32))" | sudo tee .../fan_tables
```

---

## System setting switches (MR fork, REPORT §4.6.1)

| attribute | register / bit | on | off |
|---|---|---|---|
| `copilot_key_toggle_enable` | 0x728 bit2 | Copilot key locked | unlocked |
| `ac_recovery_toggle_enable` | 0x726 bit3 | auto power-on when AC connected | disabled |
| `usb_charge_s5_toggle_enable` | 0x767 bit4 | charge USB ports while system off (S5) | disabled |

```sh
cat .../copilot_key_toggle_enable     # 0/1
echo 1 | sudo tee .../copilot_key_toggle_enable
```

These mirror the OEM `SetCopilotKey` / `UserSetAcRecoverySwitch` /
`USB_Charger_ON|OFF` (JIT-decoded IL, tokens 0x06001194 / 0x06001198 /
0x060011C2|C3).

> `ac_recovery_toggle_enable` (0x726 bit3) lives in the same byte as the
> custom-mode flag (0x726 bit7) — bit operations are independent.
> `usb_charge_s5_toggle_enable` (0x767 bit4) shares the trigger byte
> with the super-key lock trigger (bit0) etc.

---

## Other upstream attributes

```
fn_lock_toggle_enable      EC 0x74E bit4 (Fn lock status)
super_key_toggle_enable    EC 0x768 bit0 status + 0x767 bit0 trigger (Win key lock)
silent_boost               EC 0x728 bit0 (fan capped at 80% in turbo)
touchpad_toggle_enable     EC 0x7A6 bit6 (see README touchpad note)
rainbow_animation          lightbar
breathing_in_suspend       lightbar
ctgp_offset                NVIDIA CTGP
```

---

## Module parameters

| param | default | meaning |
|---|---|---|
| `force` | 0 | load without DMI match |
| `perf_key_auto` | 1 | handle the performance hotkey in-driver (cycle profile) |
| `cycle_custom` | 0 | hotkey cycle includes custom: 办公→均衡→狂暴→自定义 |
| `perf_on_battery` | 0 | allow performance/custom on battery |
