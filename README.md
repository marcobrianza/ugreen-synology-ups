# UGREEN US3000 on Synology DSM: setup and recovery

Tested on **November 17, 2026**, with a **UGREEN US3000 (DC600)** connected over USB to a **Synology DS225+**. This solution uses DSM's built-in NUT services and a modified copy of `usbhid-ups`. It requires no container, external server, or SNMP bridge.

## Tested configuration

| Component | Version / identifier |
|---|---|
| NAS | Synology DS225+, x86_64 |
| DSM | 7.4.1-90080 Update 1 |
| Observed kernel | Linux 5.10.55+ |
| UPS | UGREEN US3000, USB string DC600 |
| USB VID:PID | `2b89:ffff` |
| Original Synology driver | Generic HID 0.47, `DSM7-4-90076-260709` |
| Subdriver | Arduino HID 0.2 |
| Binary dependencies | `libusb-0.1.so.4`, `libm.so.6`, `libc.so.6` |
| Tested DSM protection setting | Customize time: **3 minutes** |

This project covers USB communication. Physical power-connector adapters had already been fitted. Reliable barrel-jack measurements were not recorded; do not use this guide to determine connector dimensions, polarity, or voltage.

## Quick recovery after a DSM update

First check whether the new DSM version already supports the UPS without modifications. Do not replace a working driver.

1. Download this repository and keep a copy outside the NAS.
2. With mains power connected, open an SSH session and run `sudo sh diagnose.sh` from the package directory.
3. If the installed driver matches the exact original archived here, or our v3, run `sudo sh install.sh`.
4. If the installer reports a **different driver**, stop. Do not overwrite a new DSM driver with this old binary. Save the new original and follow [PATCHING.md](PATCHING.md).

The installer checks the architecture and SHA-256 hashes, backs up the files currently installed, installs v3, enables `pollonly` in both active and default configurations, registers the USB ID in DSM's device list, and enables the USB service at boot. It does not change the UPS preferences in the DSM web interface.

**The installation and rollback scripts are newly automated versions of the successful manual procedure. They passed local syntax checks, and the patcher was verified, but the scripts themselves have not been run on a second NAS.** The hardware behavior described below was verified using the manual commands.

### Transfer from a Mac

Replace `USER` and `NAS_IP` with your values. Run these commands on the Mac, from the parent directory of the repository. If downloaded as a ZIP, rename the extracted directory to `ugreen-synology-ups` first.

```sh
scp -O -r ugreen-synology-ups USER@NAS_IP:ugreen-synology-ups
ssh USER@NAS_IP
```

On the NAS:

```sh
cd ~/ugreen-synology-ups
sudo sh diagnose.sh
sudo sh install.sh
```

`-O` is an uppercase letter O: it forces the legacy SCP protocol. In our setup, default SCP failed with `subsystem request failed on channel 0` because SFTP was unavailable.

### DSM settings

Open Control Panel → Hardware & Power → UPS:

- **Enable UPS support**: enabled.
- **UPS type**: USB UPS.
- **Customize time**: **3 minutes**.
- **Shut down UPS when the system enters Standby Mode**: **disabled**. The v3 driver monitors the UPS but does not include UPS shutdown command mappings.
- **Enable network UPS server**: unnecessary for this NAS alone.
- Click **Apply**.

Do not add `onlinedischarge`. This UPS reports `DISCHRG` while mains power is present. That option could turn the normal state into a false power-failure indication.

### Verify immediately and after a real reboot

```sh
upsc ups@localhost
systemctl status ups-usb.service --no-pager -l
ps aux | grep -E '[u]sbhid-ups|[u]psd|[u]psmon'
```

With mains present, expect `ups.status: OL DISCHRG`, input and output around 12 V, battery charge, and `driver.flag.pollonly: enabled`. The driver, `upsd`, and `upsmon` should be running. Two upsmon processes were normal in the tested configuration.

Reboot through DSM. Run the commands again **without first running `systemctl start`**, and check that the UPS appears in DSM. An `enabled` result alone does not prove the service actually started.

## What was wrong

Several independent issues had to be addressed:

1. `lsusb` detected UGREEN US3000 `2b89:ffff`, but `usbhid-ups` rejected it with `failed to match a subdriver` / `No matching HID UPS found`.
2. The binary already contained the Arduino subdriver, but its device table lacked the UGREEN ID. This DSM build did not expose a `subdriver` option for selecting it manually.
3. Adding the ID alone was insufficient: Arduino selected USB interface 2 and endpoints 4/5. The UPS uses interface 0, which was already accessible in `explore` mode.
4. This Arduino version only had nine timer/command mappings and no battery/status mappings. The v3 patch replaces them with eight standard read-only mappings already present elsewhere in the same binary.
5. DSM has a separate device list, `/etc/ups/nutscan-usb.h`, which also lacked `2b89:ffff`.
6. DSM could restore the active configuration from `/etc.defaults/ups/ups.conf`. Editing only `/etc/ups/ups.conf` lost `pollonly`.
7. `ups-usb.service` was static and did not start automatically. Explicitly connecting it to the boot target solved this in the tested setup.

Running the driver alone is insufficient: `upsc` queries **upsd**, and **upsmon** handles NAS protection. `Connection refused` with no processes running meant the server had not started.

## Included files

- `usbhid-ups-synology.original`: exact original driver, 366104 bytes.
- `usbhid-ups-ugreen-v3`: modified driver tested on the NAS.
- `patch_driver.py`: reproduces v3 from the exact original, checking its hash and validating ELF relocations.
- `install.sh`: guarded installation and recovery with backups.
- `restore.sh`: rolls back the changes saved by `install.sh`.
- `diagnose.sh`: read-only diagnostic checks.
- `PATCHING.md`: implementation details and guidance for a different future binary.
- `TESTED.md`: successful tests, limitations, and expected symptoms.
- `SHA256SUMS`: file integrity checks.
- `THIRD_PARTY.md`: provenance and licensing information.

The package contains no credentials, local network addresses, complete NAS logs, or NUT authentication configuration.

## Backups and rollback

`install.sh` saves the first files it encounters in `/usr/local/etc/ugreen-us3000-backup`. It does not overwrite those backups on subsequent runs. If the NAS is already modified, the backup represents that modified state, not necessarily factory defaults. Save each new original separately before making changes following an update.

To undo an installation performed by the script:

```sh
sudo sh restore.sh
```

Rollback leaves the service stopped, keeps the backup, and refuses automatic restoration if an update has changed the driver. Do not restore old configuration files onto a new DSM release without reviewing them.

The original manual session also created these separate backups:

```text
/bin/usbhid-ups.before-ugreen
/etc/ups/ups.conf.before-ugreen
/etc/ups/nutscan-usb.h.before-ugreen
/etc.defaults/ups/ups.conf.before-ugreen
```

## References

- [NUT: usbhid-ups](https://networkupstools.org/docs/man/usbhid-ups.html)
- [NUT: UGREEN US3000 Arduino HID support and missing mappings](https://github.com/networkupstools/nut/issues/3281)
- [Upstream Arduino HID source](https://github.com/networkupstools/nut/blob/master/drivers/arduino-hid.c)
- [Synology: UPS and Standby Mode](https://kb.synology.com/en-ph/DSM/help/DSM/AdminCenter/system_hardware_ups?version=7)

DSM updates may overwrite the binary, USB lists, configuration, and boot integration. Rechecking the setup after every update is part of the recovery procedure.
