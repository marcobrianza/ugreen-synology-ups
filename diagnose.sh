#!/bin/sh
# Read-only checks. Run with sudo for complete output.
printf '\n== DSM ==\n'
cat /proc/sys/kernel/syno_hw_version /etc.defaults/VERSION
printf '\n== Driver ==\n'
sha256sum /bin/usbhid-ups /usr/bin/usbhid-ups
printf '\n== USB ==\n'
lsusb
printf '\n== Service ==\n'
systemctl status ups-usb.service --no-pager -l
systemctl is-enabled ups-usb.service
printf '\n== Polling ==\n'
grep -n 'pollonly' /etc/ups/ups.conf /etc.defaults/ups/ups.conf
printf '\n== USB registration ==\n'
grep -ni '2b89' /etc/ups/nutscan-usb.h
printf '\n== UPS data ==\n'
upsc ups@localhost
printf '\n== Processes ==\n'
ps aux | grep -E '[u]sbhid-ups|[u]psd|[u]psmon'
printf '\n== Boot journal ==\n'
journalctl -b -u ups-usb.service -n 50 --no-pager
