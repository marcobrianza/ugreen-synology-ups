# Test results and limitations

Manual testing on November 17, 2026: DS225+ / DSM 7.4.1-90080 Update 1 / UGREEN US3000 2b89:ffff.

## Observed results

| Condition | Result |
|---|---|
| Mains present | OL DISCHRG, input 12.0 V, output 12.0 V, battery 96–97% |
| Mains disconnected from UPS input | OB DISCHRG, input 0.0 V, output 12.0 V |
| Runtime reported during one battery test | 873 seconds; an estimate, not a guaranteed duration |
| Mains restored | Return to OL DISCHRG, input/output 12.0 V |
| DSM service started manually | usbhid-ups, upsd, and upsmon active; upsc responds |
| Real reboot after enabling boot integration | DSM recognizes the UPS; upsc works without manually starting the service |
| Extended test outage | Battery-mode email; web and SSH become inaccessible after three minutes |
| Mains restored after protection | Web interface becomes accessible again; user confirms recovery |

Service shutdown and recovery are consistent with DSM Standby Mode. Per-volume unmount events were not independently checked in the logs. Complete battery depletion and the low-battery bit at 20% were not tested.

## Three important device behaviors

1. **OL DISCHRG with mains present** is the observed UPS state. Do not enable `onlinedischarge`: testing confirmed that OL/OB distinguishes mains from battery operation.
2. **Runtime 65535 with mains present** must not be treated as a reliable duration. On battery, the value changed to a plausible estimate. A fixed three-minute protection timer is used.
3. **Standby Mode does not necessarily power the NAS off physically.** Services stop while ping may still respond. In our test SSH returned connection refused/timeouts and the web interface stopped responding. Both recovered after mains power returned.

## Repeating the test

Start with interruptible workloads, a charged UPS, and mains connected:

1. Check OL, battery charge, the three-minute DSM setting, and disabled UPS shutdown.
2. Disconnect mains **from the UPS input only**. Keep USB and UPS-to-NAS power connected.
3. For a brief test, check OB and reconnect mains before the timer expires.
4. For a full test, wait for protection after three minutes. Access to services will be interrupted.
5. Reconnect mains to the UPS input. Wait a few minutes, then confirm DSM recovery and OL status.

There is no need to exhaust the battery. These results apply to this hardware/software combination and test; they do not establish compatibility with other models or future updates.

## Quick troubleshooting

- `No matching HID UPS found`: check the driver hash and USB VID/PID.
- `could not claim interface 2`: v1 is installed, or the Arduino interface setting was not corrected.
- Only timers, no battery data, OB despite mains: v2 or incomplete mappings.
- `upsc ... Connection refused`: check the USB service and upsd process. This alone does not establish a USB fault.
- Works after `systemctl start`, but not after reboot: check the drop-in, boot symlink, and journal.
- `pollonly` disappears: check `/etc.defaults/ups/ups.conf` too.
- `Permission denied`: use sudo; an ordinary SSH session is not root.
- SCP fails on the SFTP subsystem: use `scp -O` from the Mac.
- Web/SSH inaccessible after three minutes: this may be Standby Mode. Restore mains at the UPS input and observe recovery.
