#!/bin/sh
# Install only the exact, tested DSM driver. Run: sudo sh install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo 'Run with sudo sh install.sh'; exit 1; }
cd "$(dirname "$0")"
stock=c40952698fc8b333eba260169328c533f98c4a3dc58174774b0be87b549182c8
patched=3a14cd2a9d982ef675032a509e3396e03e5636979d70e576557c369c4fee639a
hash() { sha256sum "$1" | awk '{print $1}'; }
[ "$(uname -m)" = x86_64 ] || { echo 'Unsupported architecture'; exit 1; }
[ "$(hash usbhid-ups-ugreen-v3)" = "$patched" ] || { echo 'Invalid patched binary'; exit 1; }
current=$(hash /bin/usbhid-ups)
case "$current" in "$stock"|"$patched") ;; *) echo 'Different DSM driver: refusing to install the old binary. See PATCHING.md.'; exit 1;; esac
[ "$(hash /usr/bin/usbhid-ups)" = "$current" ] || { echo '/bin and /usr/bin contain different drivers: investigate before proceeding'; exit 1; }
for file in /etc/ups/ups.conf /etc.defaults/ups/ups.conf /etc/ups/nutscan-usb.h; do
 [ -f "$file" ] || { echo "Missing file: $file"; exit 1; }
done
grep -q 'Terminating entry' /etc/ups/nutscan-usb.h || { echo 'USB device-list format has changed'; exit 1; }
if command -v upsc >/dev/null 2>&1; then
 status=$(upsc ups@localhost ups.status 2>/dev/null || true)
 case " $status " in *' OB '*) echo 'UPS is on battery: restore mains before installing'; exit 1;; esac
fi
backup=/usr/local/etc/ugreen-us3000-backup
mkdir -p "$backup"
for pair in 'driver:/bin/usbhid-ups' 'ups.conf:/etc/ups/ups.conf' 'ups.defaults.conf:/etc.defaults/ups/ups.conf' 'nutscan-usb.h:/etc/ups/nutscan-usb.h'; do
 name=${pair%%:*}; file=${pair#*:}
 [ -e "$backup/$name" ] || cp -p "$file" "$backup/$name"
done
if [ ! -f "$backup/boot-state" ]; then
 if [ -L /etc/systemd/system/syno-bootup-done.target.wants/ups-usb.service ]; then echo enabled; else echo not-enabled; fi > "$backup/boot-state"
fi
# Stop via DSM's own unit, then replace the exact driver that passed the hash check.
systemctl stop ups-usb.service
cp usbhid-ups-ugreen-v3 /bin/usbhid-ups
chmod 755 /bin/usbhid-ups
[ "$(hash /usr/bin/usbhid-ups)" = "$patched" ] || cp usbhid-ups-ugreen-v3 /usr/bin/usbhid-ups
for file in /etc/ups/ups.conf /etc.defaults/ups/ups.conf; do
 sed -i '/^[[:space:]]*#*pollonly[[:space:]]*$/d' "$file"
 printf '\n\tpollonly\n' >> "$file"
done
if ! grep -qi '0x2b89, 0xffff,' /etc/ups/nutscan-usb.h; then
 sed -i '/\/\* Terminating entry \*\//i\	{ 0x2b89, 0xffff, "usbhid-ups" },' /etc/ups/nutscan-usb.h
fi
mkdir -p /etc/systemd/system/ups-usb.service.d
printf '[Install]\nWantedBy=syno-bootup-done.target\n' > /etc/systemd/system/ups-usb.service.d/ugreen-boot.conf
systemctl daemon-reload
systemctl enable ups-usb.service || systemctl is-enabled --quiet ups-usb.service
systemctl start ups-usb.service
upsc ups@localhost
echo 'Check DSM: USB UPS support enabled, 3 minutes, UPS shutdown disabled. Click Apply.'
echo "Backup: $backup (may contain private settings: do not publish it)."
