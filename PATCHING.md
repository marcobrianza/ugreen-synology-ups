# Modifica riproducibile e adattamento a un futuro DSM

## Originale esatto e risultato

SHA-256 originale:
`c40952698fc8b333eba260169328c533f98c4a3dc58174774b0be87b549182c8`

SHA-256 v3:
`3a14cd2a9d982ef675032a509e3396e03e5636979d70e576557c369c4fee639a`

Entrambi 366104 byte, ELF64 little-endian PIE x86_64, stripped; interprete `/lib64/ld-linux-x86-64.so.2`. Il binario originale richiede anche simboli GLIBC fino a 2.34. Essere semplicemente x86_64 non rende un altro binario compatibile.

Il patcher non compila NUT e non aggiorna la versione: modifica una copia del driver Synology mantenendone le dipendenze e il codice principale. Non e una build upstream aggiornata.

Su un computer con Python 3, dalla cartella del repository:

```sh
python3 patch_driver.py usbhid-ups-synology.original /tmp/usbhid-ups-rebuilt
shasum -a 256 /tmp/usbhid-ups-rebuilt
```

L'hash deve essere quello v3. La lettura/scrittura ELF funziona anche da macOS; il risultato puo essere eseguito solo su Linux compatibile. Il patcher produce anche un rapporto JSON accanto al file di uscita.

## Le tre modifiche della v3

### 1. Tabella identificativi USB Arduino

La struttura del sottodriver e all'indirizzo virtuale ELF `0x49940`, la funzione claim a `0x253d0`, la tabella USB a `0x498c0`. Alla prima voce vuota, indirizzo virtuale `0x49920`, **offset file `0x48920`**, sono stati aggiunti i due interi little-endian da 16 bit:

```text
VID 0x2b89, PID 0xffff -> 89 2b ff ff
```

Le voci Arduino esistenti restano nella tabella e segue ancora una voce nulla di terminazione. Questo era tutto cio che faceva la v1: il riconoscimento riusciva, ma l'accesso falliva sull'interfaccia 2.

### 2. Parametri USB

La funzione claim Arduino sovrascriveva i parametri generici impostando interfaccia 2 ed endpoint 4/5. Alla v2 sono state neutralizzate **due istruzioni**, intervallo file `[0x253f9, 0x2540a)`, con 17 byte `0x90` (NOP).

Si mantengono quindi i valori generici iniziali: interfaccia 0, indice descrittore 0, endpoint input/output 1. La `pop rbx` a `0x253f8`, il valore di ritorno e la struttura della funzione sono conservati.

Questa modifica influenza il sottodriver Arduino della copia: il file risultante e dedicato all'Ugreen di questa prova, non e un sostituto universale per dispositivi Arduino.

### 3. Mappature HID verso NUT

La tabella Arduino originaria a `0x499a0` aveva nove record da 56 byte di timer/comandi e un terminatore a `0x49b98`. La v3 sostituisce i record con otto associazioni standard, copiate da altre tabelle interne dello stesso binario:

| Variabile | Percorso HID | Record sorgente (VA) |
|---|---|---|
| battery.charge | UPS.PowerSummary.RemainingCapacity | 0x48320 |
| battery.charge.low | UPS.PowerSummary.RemainingCapacityLimit | 0x49d78 |
| battery.runtime | UPS.PowerSummary.RunTimeToEmpty | 0x48400 |
| input.voltage | UPS.PowerConverter.Input.[1].Voltage | 0x4c1f0 |
| output.voltage | UPS.PowerConverter.Output.Voltage | 0x4c110 |
| BOOL: rete presente | UPS.PowerSummary.PresentStatus.ACPresent | 0x48ba8 |
| BOOL: scarica | UPS.PowerSummary.PresentStatus.Discharging | 0x48be0 |
| BOOL: batteria bassa | UPS.PowerSummary.PresentStatus.BelowRemainingCapacityLimit | 0x48c88 |

Queste mappature non hanno flag di scrittura ne comandi istantanei. Nono record e terminatore sono azzerati. Le tabelle di conversione dei booleani sono quelle generiche gia presenti nel binario.

Il file e PIE: cambiare soltanto i puntatori nella tabella dati NON basta, perche il loader li riscrive attraverso `.rela.dyn`. Il patcher aggiorna anche le 27 rilocazioni `R_X86_64_RELATIVE` dei vecchi nove record. Le nuove mappature richiedono 24 rilocazioni: le tre rimanenti vengono dirette allo stesso primo puntatore con identico valore, quindi sono scritture ridondanti e idempotenti. Il patcher simula l'applicazione di queste rilocazioni e verifica che gli otto record coincidano esattamente con quelli sorgente e che il terminatore resti nullo.

## Se l'hash del nuovo DSM e diverso

**Non riutilizzare gli offset precedenti. Il patcher rifiuta intenzionalmente altri input.**

1. Provare il nuovo driver originale: Synology potrebbe aver aggiunto il supporto nativo.
2. Conservare una copia del nuovo binario, hash, versione DSM, output `usbhid-ups -h` e `-L`, architettura e librerie.
3. Provare in un percorso separato, senza sostituire `/bin/usbhid-ups`:

```sh
sudo /bin/usbhid-ups -s ugreen_probe -x port=auto -x vendorid=2b89 -x productid=ffff -x pollonly -u root -d 1
```

Eseguire prove dirette solo con il servizio USB fermo, per non contendere il dispositivo. Dopo le prove riavviare il servizio. Non usare `-k`, che richiede lo spegnimento dell'UPS.

4. Se serve analisi, `-x explore -DD` permette di leggere il descrittore HID, ma il suo `ups.status` non e una misura attendibile della protezione. Non usarlo come driver operativo.
5. Individuare di nuovo struttura Arduino, funzione claim, tabella degli identificativi, impostazioni USB, mappature e rilocazioni ELF. Usare disassemblatore/analisi ELF e sorgente upstream per orientarsi, senza assumere che il fork Synology coincida con una release NUT precisa.
6. Preferire il supporto nativo di un nuovo sottodriver quando disponibile; se si adatta la patch, aggiornare assert, hash e documentazione. Valutare una build compatibile da sorgente se la struttura non si presta alla stessa modifica.
7. Verificare nell'ordine: rete presente, blackout breve, ritorno rete, integrazione NUT di DSM, impostazioni pagina UPS, avvio automatico dopo un vero reboot e ciclo di protezione di 3 minuti.
8. Solo dopo le verifiche sostituire il driver operativo e conservare anche il nuovo originale. Non copiare vecchie librerie o vecchie configurazioni sopra un sistema aggiornato.

## Integrazione DSM che deve restare presente

- `/etc/ups/nutscan-usb.h`: voce `{ 0x2b89, 0xffff, "usbhid-ups" },` prima del terminatore. Lo script DSM estrae il quarto campo delimitato da spazi: mantenere il formato della riga.
- `/tmp/ups/ups_drv.list`: cache temporanea della lista; viene ricreata, non e un backup persistente.
- `/etc/ups/ups.conf` e `/etc.defaults/ups/ups.conf`: `pollonly` nella sezione `[ups]`.
- `/etc/systemd/system/ups-usb.service.d/ugreen-boot.conf`:

```ini
[Install]
WantedBy=syno-bootup-done.target
```

Poi `systemctl daemon-reload` e `systemctl enable ups-usb.service`. Nella prova DSM ha mostrato anche un avviso su `[Install]`, ma ha creato il link in `syno-bootup-done.target.wants` e `is-enabled` ha restituito `enabled`. Il risultato effettivo e stato verificato dopo il riavvio.

Il servizio originale contiene gia `After=syno-bootup-done.target`: non e stato riscritto. Non sostituire gli script `ups-usb.sh`, `ups-net.sh` o `synoupscommon` con copie di questa sessione.
