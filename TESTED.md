# Prove e limiti

Collaudo manuale del 17 novembre 2026, DS225+ / DSM 7.4.1-90080 Update 1 / UGREEN US3000 2b89:ffff.

## Risultati osservati

| Situazione | Risultato |
|---|---|
| Rete presente | OL DISCHRG, input 12.0 V, output 12.0 V, batteria 96-97% |
| Rete scollegata dall'ingresso UPS | OB DISCHRG, input 0.0 V, output 12.0 V |
| Autonomia durante una prova a batteria | 873 secondi (stima, non durata garantita) |
| Rete ripristinata | ritorno a OL DISCHRG, input/output 12.0 V |
| Avvio manuale servizio DSM | usbhid-ups, upsd e upsmon attivi; upsc risponde |
| Riavvio reale dopo abilitazione al boot | pagina DSM riconosce UPS; upsc legge senza avvio manuale |
| Blackout prolungato di prova | email di funzionamento a batteria; dopo 3 minuti web e SSH diventano inaccessibili |
| Ritorno corrente dopo la protezione | interfaccia web torna accessibile; utente conferma ripresa del funzionamento |

La fermata dei servizi e la successiva ripresa sono coerenti con Standby Mode di DSM. Non e stata verificata direttamente nei log la sequenza di smontaggio di ciascun volume. Non e stato simulato l'esaurimento completo della batteria o verificato il bit batteria bassa al 20%.

## Tre particolarita da ricordare

1. **OL DISCHRG con rete presente** e il valore osservato sull'UPS. Non attivare `onlinedischarge`, perche le prove hanno verificato che il discriminante utile e OL/OB.
2. **65535 di autonomia con rete presente** non va usato come previsione affidabile. A batteria il valore e cambiato in una stima plausibile. Si usa un timer fisso di 3 minuti.
3. **Standby Mode non significa necessariamente spegnimento fisico**: i servizi si fermano e il NAS puo continuare a rispondere al ping. Nel collaudo SSH dava connection refused/timeout e web non rispondeva; al ritorno della rete il sistema e tornato utilizzabile.

## Ripetere il collaudo

Con servizi e lavori interrompibili, UPS carico e rete presente:

1. Verificare OL, carica, impostazione DSM di 3 minuti e spegnimento UPS disattivato.
2. Scollegare solo l'alimentazione **in ingresso all'UPS**. Lasciare collegati USB e alimentazione UPS → NAS.
3. Per una prova breve, controllare OB e ripristinare la rete prima del timer.
4. Per il collaudo completo, attendere la protezione dopo 3 minuti: l'accesso ai servizi verra interrotto.
5. Ripristinare la rete all'ingresso dell'UPS. Attendere alcuni minuti e verificare il ritorno di DSM e lo stato OL.

Non e necessario far esaurire la batteria. Il funzionamento osservato vale per questa combinazione e questa prova, non dimostra compatibilita con altri modelli o futuri aggiornamenti.

## Diagnosi rapida

- `No matching HID UPS found`: verificare hash del driver e VID/PID.
- `could not claim interface 2`: e stata usata la v1 o non e stata corretta l'impostazione Arduino.
- Solo timer, niente batteria, OB anche con rete: v2 o mappature incomplete.
- `upsc ... Connection refused`: controllare servizio USB e presenza di upsd; non significa da solo che USB sia guasta.
- Funziona con `systemctl start`, non dopo reboot: verificare drop-in, symlink di boot e journal.
- `pollonly` scompare: controllare anche `/etc.defaults/ups/ups.conf`.
- `Permission denied`: usare sudo, la sessione SSH ordinaria non e root.
- SCP fallisce su SFTP: usare `scp -O` dal Mac.
- Dopo 3 minuti web/SSH non accessibili: puo essere Standby Mode, ripristinare la rete in ingresso e osservare la ripresa.
