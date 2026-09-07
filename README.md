# Radio Orania Sender Installer

'n Eenvoudige, betroubare Debian-gebaseerde radiosender met outomatiese stroom-failover, noodmusiek en web-gebaseerde media bestuur.

---

## Kenmerke

* Internet radiostroom afspeel
* Outomatiese failover na noodmusiek
* Outomatiese terugskakeling na die stroom
* ALSA klankuitset
* Systemd diens wat as 'n toegewyde, onbevoorregte gebruiker loop
* File Browser vir media bestuur
* Heartbeat ondersteuning
* `radioctl` beheerpaneel vir status, herbegin, logs en opdatering
* Debian 13 ondersteuning
* Eenvoudige installasie

---

## Hoe dit Werk

```text
                    Internet Stroom
                           │
                           ▼
                      Liquidsoap
                           │
            ┌──────────────┴──────────────┐
            │                             │
            ▼                             ▼
     Stroom beskikbaar             Stroom af
            │                             │
            ▼                             ▼
      Direkte stroom            Musiek + Sweepers
            │                             │
            └──────────────┬──────────────┘
                           │
                           ▼
                        ALSA
                           │
                           ▼
                       Klankkaart
                           │
                           ▼
                     FM Sender
```

---

## Vereistes

* Debian 13
* Internetverbinding
* ALSA-versoenbare klankkaart
* Root toegang

Die installer waarsku (maar blokkeer nie noodwendig nie) as dit op 'n ander weergawe as Debian 13 loop.

---

## Installasie

Kloon die projek:

```bash
git clone https://github.com/Schalk-Christiaan/Radio-Sender-Installer.git
cd Radio-Sender-Installer
```

Begin die installer:

```bash
sudo bash install.sh
```

Verbose modus (wys volledige uitset van elke stap op die skerm; alles word in elk geval altyd na `installer.log` geskryf):

```bash
sudo bash install.sh --verbose
```

Die installer word aan die einde outomaties na `/opt/radio-orania/installer` gekopieer sodat `radioctl reconfigure` en `radioctl update` later sonder die oorspronklike kloon kan werk.

---

## Sekuriteit

* Die radio-, File Browser- en heartbeat-dienste loop almal as 'n toegewyde, onbevoorregte gebruiker (`radio-orania`), nie as root nie.
* Gebruikersinvoer tydens opstelling word gevalideer en veilig ge-kwoteer voordat dit in konfigurasie- of stelsel-lêers geskryf word.
* `environment.conf` en File Browser se `credentials.txt` is slegs vir die eienaar leesbaar (`chmod 600`).

---

## Media Struktuur

Plaas musiek en sweepers in:

```text
/opt/radio-orania/media
├── Musiek
└── Sweepers
```

---

## File Browser

Indien geaktiveer tydens installasie kan media bestuur word deur File Browser.

Die URL, gebruiker en wagwoord word gestoor in:

```text
/opt/radio-orania/filebrowser/credentials.txt
```

'n Herkonfigurasie skep nie 'n nuwe wagwoord of oorskryf bestaande File Browser-gebruikers nie — die databasis word slegs geskep by 'n eerste installasie.

---

## `radioctl` Beheerpaneel

Na installasie is 'n `radioctl` opdrag beskikbaar om die sender te bestuur sonder om `systemctl`/`journalctl` paaie te onthou:

```text
radioctl status         Wys status van al die dienste, sender naam en stroom URL
radioctl start          Begin die radio-diens
radioctl stop           Stop die radio-diens
radioctl restart        Herbegin die radio-diens
radioctl logs [-f]      Wys onlangse logs (-f om te volg)
radioctl test-stream    Toets of die stroom URL bereikbaar is
radioctl media          Wys File Browser toegangsbesonderhede
radioctl backup         Skep 'n rugsteun van die mediavouer
radioctl reconfigure    Loop die opstelling-assistent weer
radioctl update         Trek die jongste weergawe en herinstalleer
```

`start`/`stop`/`restart`/`backup`/`reconfigure`/`update` vereis root (`sudo radioctl ...`).

---

## Logs

Installer:

```text
installer.log
```

Radio diens:

```bash
journalctl -u radio-orania -f
```

File Browser:

```text
/opt/radio-orania/filebrowser/filebrowser.log
```

---

## Verwydering

Om die installasie te verwyder:

```bash
sudo bash uninstall.sh
```

Indien daar media in `/opt/radio-orania/media` is, bied die uninstaller eers aan om dit na 'n `.tar.gz` te rugsteun voor verwydering.

Dit verwyder:

* Radio Orania diens
* File Browser diens
* Heartbeat
* Outo-restart timer
* `radioctl` beheerpaneel
* Die `radio-orania` diens-gebruiker
* Alle Radio Orania data

---

## Projek Status

### V1.0

Voltooi:

* Installer
* Liquidsoap integrasie
* Outomatiese failover
* Outomatiese herstel na stroom
* File Browser
* Heartbeat ondersteuning
* Validation
* Uninstaller
* Toegewyde, onbevoorregte diens-gebruiker
* `radioctl` beheerpaneel
* ShellCheck CI

### Beplan vir V1.1

* Verdere hardening
* Service Watchdog
* File Browser Wagwoord Reset

---
