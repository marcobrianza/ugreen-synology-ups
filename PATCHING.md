# Reproducing the patch and adapting it to a future DSM release

## Exact input and output

Original SHA-256:
`c40952698fc8b333eba260169328c533f98c4a3dc58174774b0be87b549182c8`

v3 SHA-256:
`3a14cd2a9d982ef675032a509e3396e03e5636979d70e576557c369c4fee639a`

Both files are 366104 bytes: stripped ELF64 little-endian PIE x86_64 executables using `/lib64/ld-linux-x86-64.so.2`. The original binary requires GLIBC symbols up to version 2.34. Matching the x86_64 architecture alone does not guarantee compatibility.

The patcher does not compile NUT or upgrade its version. It modifies a copy of the Synology driver while preserving its dependencies and main driver code. The result is not an updated upstream build.

On a computer with Python 3, from this repository directory:

```sh
python3 patch_driver.py usbhid-ups-synology.original /tmp/usbhid-ups-rebuilt
shasum -a 256 /tmp/usbhid-ups-rebuilt
```

The hash must match v3 above. ELF file manipulation works on macOS too, but the resulting executable requires compatible Linux. The patcher also writes a JSON verification report next to the output file.

## The three v3 changes

### 1. Arduino USB device table

The subdriver structure is at ELF virtual address `0x49940`, its claim function at `0x253d0`, and its USB table at `0x498c0`. The first empty entry, virtual address `0x49920`, **file offset `0x48920`**, receives two little-endian 16-bit integers:

```text
VID 0x2b89, PID 0xffff -> 89 2b ff ff
```

Existing Arduino entries remain, followed by a null terminating entry. This was the only v1 change: recognition succeeded, but claiming interface 2 failed.

### 2. USB interface and endpoints

Arduino's claim function overwrote the generic settings with interface 2 and endpoints 4/5. In v2, **two instructions**, file range `[0x253f9, 0x2540a)`, were replaced with 17 `0x90` bytes (NOPs).

This preserves the generic initial values: interface 0, descriptor index 0, and input/output endpoints 1. The `pop rbx` at `0x253f8`, the return value, and the function structure remain intact.

This changes the Arduino subdriver in the patched copy. The resulting binary is dedicated to this UGREEN setup; it is not a universal replacement for Arduino devices.

### 3. HID-to-NUT mappings

The original Arduino table at `0x499a0` contained nine 56-byte timer/command records followed by a terminator at `0x49b98`. v3 replaces them with eight standard mappings copied from other internal tables in the same binary:

| Variable | HID path | Source record (VA) |
|---|---|---|
| battery.charge | UPS.PowerSummary.RemainingCapacity | 0x48320 |
| battery.charge.low | UPS.PowerSummary.RemainingCapacityLimit | 0x49d78 |
| battery.runtime | UPS.PowerSummary.RunTimeToEmpty | 0x48400 |
| input.voltage | UPS.PowerConverter.Input.[1].Voltage | 0x4c1f0 |
| output.voltage | UPS.PowerConverter.Output.Voltage | 0x4c110 |
| BOOL: mains present | UPS.PowerSummary.PresentStatus.ACPresent | 0x48ba8 |
| BOOL: discharging | UPS.PowerSummary.PresentStatus.Discharging | 0x48be0 |
| BOOL: low battery | UPS.PowerSummary.PresentStatus.BelowRemainingCapacityLimit | 0x48c88 |

These mappings contain no write flags or instant commands. The ninth record and terminator are zeroed. Boolean conversion tables are the generic ones already present in the binary.

Because this is a PIE executable, changing pointers in the data table alone is insufficient: the loader rewrites them through `.rela.dyn`. The patcher updates the 27 `R_X86_64_RELATIVE` relocations belonging to the original nine records. The new mappings need 24 relocations. The remaining three target the same first pointer with the same value, making them redundant, idempotent writes. The patcher simulates these relocations and verifies that all eight records exactly match their source records and the terminator remains null.

## If a new DSM driver has a different hash

**Do not reuse these offsets. The patcher deliberately rejects other input files.**

1. Test the new original driver first: Synology may have added native support.
2. Save the new binary, its hash, DSM version, `usbhid-ups -h` and `-L` output, architecture, and library dependencies.
3. Test separately before replacing the operational driver:

```sh
sudo /bin/usbhid-ups -s ugreen_probe -x port=auto -x vendorid=2b89 -x productid=ffff -x pollonly -u root -d 1
```

Run direct driver tests only while the USB service is stopped, to avoid competing for the device. Restart the service afterwards. Do not use `-k`, which requests UPS power-off.

4. If needed, `-x explore -DD` reads the HID descriptor. Its `ups.status` is not a reliable protection status; do not use explore mode operationally.
5. Locate the Arduino structure, claim function, USB ID table, USB settings, mappings, and ELF relocations again. Use ELF/disassembly tools and upstream source as references; do not assume the Synology fork matches a particular upstream release.
6. Prefer native support in a newer subdriver when available. If adapting this patch, update assertions, hashes, and documentation. Consider a compatible source build if the new structure does not support this approach.
7. Verify, in order: mains present, brief outage, mains restoration, DSM NUT integration, web settings, automatic startup after a real reboot, and the full three-minute protection cycle.
8. Only then replace the operational driver, keeping the new original too. Do not overwrite a newer system with old libraries or configuration files.

## DSM integration that must remain in place

- `/etc/ups/nutscan-usb.h`: add `{ 0x2b89, 0xffff, "usbhid-ups" },` before the terminator. DSM extracts the fourth space-delimited field; preserve the line format.
- `/tmp/ups/ups_drv.list`: temporary device-list cache. It is recreated and is not a persistent backup.
- `/etc/ups/ups.conf` and `/etc.defaults/ups/ups.conf`: enable `pollonly` in section `[ups]`.
- `/etc/systemd/system/ups-usb.service.d/ugreen-boot.conf`:

```ini
[Install]
WantedBy=syno-bootup-done.target
```

Then run `systemctl daemon-reload` and `systemctl enable ups-usb.service`. During testing, DSM also printed an `[Install]` warning, but created the link in `syno-bootup-done.target.wants` and returned `enabled` from `is-enabled`. Actual startup was verified after reboot.

The original service already includes `After=syno-bootup-done.target`; it was not rewritten. Do not replace `ups-usb.sh`, `ups-net.sh`, or `synoupscommon` with archived copies from this session.
