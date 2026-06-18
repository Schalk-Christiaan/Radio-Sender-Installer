# Radio Orania Sender Installer

'n Eenvoudige, betroubare Debian-gebaseerde radiosender met outomatiese stroom-failover, noodmusiek en web-gebaseerde media bestuur.

---

## Kenmerke

* Internet radiostroom afspeel
* Outomatiese failover na noodmusiek
* Outomatiese terugskakeling na die stroom
* ALSA klankuitset
* Systemd diens
* File Browser vir media bestuur
* Heartbeat ondersteuning
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

Verbose modus:

```bash
sudo bash install.sh --verbose
```

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

Dit verwyder:

* Radio Orania diens
* File Browser diens
* Heartbeat
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

### Beplan vir V1.1

* Verdere hardening
* Service Watchdog
* File Browser Wagwoord Reset

---

