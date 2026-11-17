# UGREEN US3000 su Synology DSM: ripristino rapido

Soluzione verificata il **17 novembre 2026** per collegare via USB un **UGREEN US3000 (DC600)** a un **Synology DS225+**. Usa il NUT incluso in DSM con una copia modificata del driver `usbhid-ups`: nessun container, nessun server esterno, nessun SNMP.

## Configurazione verificata

| Componente | Versione / identificativo |
|---|---|
| NAS | Synology DS225+, x86_64 |
| DSM | 7.4.1-90080 Update 1 |
| Kernel osservato | Linux 5.10.55+ |
| UPS | UGREEN US3000, stringa USB DC600 |
| USB VID:PID | `2b89:ffff` |
| Driver Synology originale | Generic HID 0.47, `DSM7-4-90076-260709` |
| Sottodriver | Arduino HID 0.2 |
| Librerie del binario | `libusb-0.1.so.4`, `libm.so.6`, `libc.so.6` |
| Protezione DSM collaudata | Customize time: **3 minuti** |

Questa soluzione riguarda la comunicazione USB. L'adattamento fisico dei connettori di alimentazione era gia stato effettuato. Non sono state registrate misure affidabili dei barrel jack: non usare questo documento per sceglierne dimensioni, polarita o tensioni.

## Ripristino dopo un aggiornamento: due percorsi

Prima controllare se il nuovo DSM riconosce gia l'UPS senza modifiche. Non sostituire un driver funzionante.

1. Scaricare il repository e conservarlo anche fuori dal NAS.
2. Con rete elettrica presente, collegarsi via SSH ed eseguire `sudo sh diagnose.sh` dalla cartella del pacchetto.
3. Se il driver e ancora quello originale esatto di questa versione, o e gia la nostra v3, usare `sudo sh install.sh`.
4. Se lo script segnala **driver diverso**, fermarsi: non copiare il vecchio binario sopra quello del nuovo DSM. Salvare il nuovo originale e seguire [PATCHING.md](PATCHING.md).

Lo script controlla SHA-256 e architettura, salva i file che trova sul NAS, installa la v3, abilita `pollonly` nella configurazione corrente e predefinita, registra l'USB ID nella lista DSM e collega il servizio USB al boot. Non cambia automaticamente le preferenze della pagina UPS.

**Gli script di installazione e ripristino sono una nuova automazione delle operazioni manuali riuscite: hanno superato controlli locali di sintassi e verifiche del patcher, ma non sono stati eseguiti su un secondo NAS.** Il comportamento hardware riportato sotto e stato verificato con i comandi manuali.

### Trasferimento dal Mac

Sostituire `UTENTE` e `IP_NAS` con i propri dati. Eseguire questi comandi sul Mac, dalla cartella superiore al repository:

```sh
scp -O -r ugreen-synology-ups UTENTE@IP_NAS:ugreen-synology-ups
ssh UTENTE@IP_NAS
```

Sul NAS:

```sh
cd ~/ugreen-synology-ups
sudo sh diagnose.sh
sudo sh install.sh
```

L'opzione `-O` e la lettera O maiuscola: forza il protocollo SCP classico. Nel nostro caso lo SCP predefinito falliva con `subsystem request failed on channel 0` perche SFTP non era disponibile.

### Impostazioni DSM

Control Panel → Hardware & Power → UPS:

- **Enable UPS support**: attivo.
- **UPS type**: USB UPS.
- **Customize time**: **3 minuti**.
- **Shut down UPS when the system enters Standby Mode**: **disattivato**. La v3 e un driver di monitoraggio senza le mappature dei comandi di spegnimento UPS.
- **Enable network UPS server**: non necessario per questo NAS.
- Premere **Apply**.

Non aggiungere `onlinedischarge`: con questo UPS la rete presente viene riportata insieme a `DISCHRG`. Quell'opzione potrebbe trasformare una situazione normale in una falsa segnalazione di blackout.

### Verifica immediata e dopo un vero riavvio

```sh
upsc ups@localhost
systemctl status ups-usb.service --no-pager -l
ps aux | grep -E '[u]sbhid-ups|[u]psd|[u]psmon'
```

Con rete presente attendersi `ups.status: OL DISCHRG`, ingresso e uscita circa 12 V, carica batteria e `driver.flag.pollonly: enabled`. Devono risultare attivi driver, `upsd` e `upsmon` (due processi upsmon sono normali nella configurazione osservata).

Riavviare da DSM. Dopo il riavvio ripetere i comandi **senza eseguire prima `systemctl start`** e verificare che la pagina UPS riconosca il dispositivo. Il solo risultato `enabled` non dimostra che il servizio sia effettivamente partito.

## Qual era il problema

C'erano piu blocchi distinti:

1. `lsusb` vedeva UGREEN US3000 `2b89:ffff`, ma `usbhid-ups` lo scartava: `failed to match a subdriver` / `No matching HID UPS found`.
2. Il sottodriver Arduino era gia nel binario, ma l'identificativo UGREEN non era nella sua tabella. Il driver DSM non esponeva l'opzione `subdriver` per sceglierlo manualmente.
3. Aggiungere solo l'identificativo non bastava: Arduino impostava l'interfaccia USB 2 e gli endpoint 4/5. L'UPS usa l'interfaccia 0, gia accessibile in modalita `explore`.
4. In questa versione Arduino aveva solo nove mappature di timer/comandi: mancavano le mappature di batteria e stato. La v3 le sostituisce con otto mappature standard di sola lettura gia presenti nel binario.
5. DSM usa una lista di riconoscimento separata, `/etc/ups/nutscan-usb.h`, dove mancava `2b89:ffff`.
6. La configurazione corrente poteva essere ripristinata da `/etc.defaults/ups/ups.conf`: modificare solo `/etc/ups/ups.conf` perdeva `pollonly`.
7. Il servizio `ups-usb.service` era statico e non partiva automaticamente. Un collegamento esplicito al target di boot ha risolto nella configurazione provata.

Avviare il driver a mano non basta: `upsc` interroga **upsd**, e **upsmon** gestisce la protezione del NAS. `Connection refused` con processi assenti indicava che il server non era avviato.

## File inclusi

- `usbhid-ups-synology.original`: copia esatta del driver originale, 366104 byte.
- `usbhid-ups-ugreen-v3`: copia modificata e collaudata sul NAS.
- `patch_driver.py`: riproduce la v3 a partire dall'originale esatto, con controllo hash e verifica delle rilocazioni ELF.
- `install.sh`: ripristino assistito, con controllo versione e backup.
- `restore.sh`: annulla le modifiche salvate da `install.sh`.
- `diagnose.sh`: controlli di sola lettura.
- `PATCHING.md`: dettagli per adattare un futuro binario diverso.
- `TESTED.md`: prove riuscite, limiti e sintomi attesi.
- `SHA256SUMS`: integrita dei file inclusi.
- `THIRD_PARTY.md`: provenienza e licenze.

Non sono inclusi credenziali, indirizzi della rete locale, log completi del NAS o configurazioni di autenticazione NUT.

## Backup e ritorno allo stato precedente

`install.sh` conserva i primi file trovati in `/usr/local/etc/ugreen-us3000-backup`. Non sovrascrive i backup alle esecuzioni successive. Se la macchina e gia modificata, quei backup rappresentano lo stato modificato di quel momento, non necessariamente lo stato originale di fabbrica. Conservare a parte il nuovo originale prima di qualsiasi modifica dopo un aggiornamento.

Per annullare l'installazione fatta dallo script:

```sh
sudo sh restore.sh
```

Lo script lascia il servizio fermo, conserva il backup e rifiuta un ripristino automatico se il driver e cambiato dopo un aggiornamento. Non ripristinare vecchie configurazioni sopra un DSM nuovo senza esaminarle.

Durante la sessione manuale iniziale sono stati creati anche questi backup, distinti da quelli dello script:

```text
/bin/usbhid-ups.before-ugreen
/etc/ups/ups.conf.before-ugreen
/etc/ups/nutscan-usb.h.before-ugreen
/etc.defaults/ups/ups.conf.before-ugreen
```

## Riferimenti

- [NUT: usbhid-ups](https://networkupstools.org/docs/man/usbhid-ups.html)
- [NUT: UGREEN US3000 con Arduino HID e mappature mancanti](https://github.com/networkupstools/nut/issues/3281)
- [Sorgente upstream Arduino HID](https://github.com/networkupstools/nut/blob/master/drivers/arduino-hid.c)
- [Synology: UPS e Standby Mode](https://kb.synology.com/en-ph/DSM/help/DSM/AdminCenter/system_hardware_ups?version=7)

Gli aggiornamenti DSM possono sovrascrivere binario, liste USB, configurazioni e integrazione di avvio. La verifica dopo ogni aggiornamento fa parte della procedura.
