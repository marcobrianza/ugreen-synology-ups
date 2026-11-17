#!/bin/sh
# Restore the state saved by install.sh. Does not reboot or remove the backup.
set -eu
[ "$(id -u)" = 0 ] || { echo 'Eseguire con sudo sh restore.sh'; exit 1; }
backup=/usr/local/etc/ugreen-us3000-backup
for name in driver ups.conf ups.defaults.conf nutscan-usb.h boot-state; do
 [ -f "$backup/$name" ] || { echo "Backup mancante: $backup/$name"; exit 1; }
done
current=$(sha256sum /bin/usbhid-ups | awk '{print $1}')
case "$current" in
 c40952698fc8b333eba260169328c533f98c4a3dc58174774b0be87b549182c8|3a14cd2a9d982ef675032a509e3396e03e5636979d70e576557c369c4fee639a) ;;
 *) echo 'Driver cambiato dopo un aggiornamento: non ripristino automaticamente vecchi file'; exit 1;;
esac
systemctl stop ups-usb.service
cp -p "$backup/driver" /bin/usbhid-ups
if ! cmp -s /usr/bin/usbhid-ups "$backup/driver"; then cp -p "$backup/driver" /usr/bin/usbhid-ups; fi
cp -p "$backup/ups.conf" /etc/ups/ups.conf
cp -p "$backup/ups.defaults.conf" /etc.defaults/ups/ups.conf
cp -p "$backup/nutscan-usb.h" /etc/ups/nutscan-usb.h
rm -f /etc/systemd/system/ups-usb.service.d/ugreen-boot.conf
if [ "$(cat "$backup/boot-state")" = not-enabled ]; then
 rm -f /etc/systemd/system/syno-bootup-done.target.wants/ups-usb.service
fi
systemctl daemon-reload
echo 'Stato precedente ripristinato; backup conservato. Il driver originale potrebbe non riconoscere UGREEN.'
echo 'Il servizio rimane fermo: verificare configurazione prima di riavviarlo.'
