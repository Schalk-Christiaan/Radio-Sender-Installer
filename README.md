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
* Opsionele beheerpaneel-skerm wat outomaties by SSH- of fisiese-skerm-aanmelding verskyn
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
radioctl set <S> <W>    Verander 'n instelling (STREAM_URL, MUSIC_WEIGHT, SWEEPER_WEIGHT)
radioctl passwords      Wys al die gestoorde wagwoorde (File Browser, beheerpaneel, monitor)
radioctl reconfigure    Loop die opstelling-assistent weer
radioctl update         Trek die jongste weergawe en herinstalleer
radioctl uninstall      Verwyder die hele installasie
```

`start`/`stop`/`restart`/`backup`/`set`/`passwords`/`reconfigure`/`update`/`uninstall` vereis root (`sudo radioctl ...`).

---

## Beheerpaneel-skerm

Opsioneel tydens installasie: 'n volskerm, outomaties-vernuwende beheerpaneel wat verskyn sodra jy aanmeld — hetsy via SSH, hetsy op 'n skerm wat fisies aan die toestel gekoppel is (tty1 word outomaties aangemeld).

Dit loop onder 'n aparte, beperkte `radio-admin` gebruiker (nie root nie) met slegs toegang tot `radioctl` via `sudo`. Die gebruiker en wagwoord word een keer gewys tydens installasie, en gestoor in:

```text
/opt/radio-orania/config/radio-admin-credentials.txt
```

Vanaf die skerm: `[S]` begin, `[T]` stop, `[R]` herbegin, `[L]` logs, `[P]` luister, `[M]` media-besonderhede, `[B]` rugsteun, `[C]` instellings, `[Q]` verlaat na 'n gewone shell. 'n Lewendige ON AIR-aanduiding en klankvlak-balk wys reg op dieselfde skerm — daar's geen aparte venster of oorname van die terminaal nie.

### Luister

`[P]` speel presies dieselfde klank wat na die aux/ALSA-uitset gaan (stroom óf noodmusiek, wat ook al werklik op-lug is) plaaslik via `mpv`, met 'n klankvlak-balk wat regstreeks op die dashboard opdateer. Druk `[P]` weer om te stop. (`radioctl monitor-url` gee die onderliggende netwerk-URL indien jy dit elders, bv. in 'n blaaiser, wil oopmaak.)

### Instellings

`[C]` gee toegang tot 'n klein kieslys om fisies op die dashboard te verander, sonder om die opstelling-assistent oor te doen:

* Stroom URL en musiek/sweeper-verhouding verander (word dadelik toegepas en die diens herbegin)
* Al die gestoorde wagwoorde sien (File Browser, beheerpaneel, monitor)
* Sagteware opdateer, herkonfigureer, of die hele installasie verwyder (met bevestiging)

Dit werk deur 'n klein plaaslike Icecast-aftakking wat Liquidsoap direk voed (`output.icecast`) — dieselfde reeds-berekende mengsel word bloot ook daarheen gestuur.

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
* `radioctl` en die beheerpaneel-skerm (insluitend die `radio-admin` gebruiker)
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
* Opsionele beheerpaneel-skerm (SSH + fisiese skerm)
* ShellCheck CI

### Beplan vir V1.1

* Verdere hardening
* Service Watchdog
* File Browser Wagwoord Reset

---
