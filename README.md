# Radio Orania Sender Installer

'n Eenvoudige, betroubare Debian-gebaseerde radiosender met outomatiese stroom-failover, noodmusiek en web-gebaseerde media bestuur.

---

## Kenmerke

* Internet radiostroom afspeel
* Opsionele rugsteun-stroom voor daar na noodmusiek oorgeskakel word
* Outomatiese failover na noodmusiek (insluitend stilte-opsporing - skakel ook oor as 'n stroom "dooie lug" uitstuur, nie net by 'n werklike ontkoppeling nie)
* Outomatiese terugskakeling na die stroom
* Klankvlak-egalisering tussen stroom en plaaslike musiek
* Begrensde skok-buffer (instelbaar) wat verhoed dat 'n FM-vertraging oor lang looptye onbeperk opbou
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
              Hoofstroom  →  Rugsteun-stroom  →  Musiek + Sweepers
             (opsioneel af/stil)  (opsioneel af/stil)
                           │
                           ▼
                 Skok-buffer (begrens vertraging)
                           │
                           ▼
                      Liquidsoap
                           │
                           ▼
              Klankvlak-egalisering (normalize)
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

Elke bron (hoofstroom en rugsteun-stroom) word deurlopend vir stilte gemonitor - as een "dooie lug" uitstuur (bv. 'n koderfout by die bron) terwyl dit tegnies nog gekoppel is, skakel Liquidsoap outomaties na die volgende bron in die ry oor. `radioctl status` en die beheerpaneel-skerm wys watter bron op enige oomblik werklik op-lug is.

### Waarom FM-vertraging oor tyd kan opbou

Die netwerkstroom en die rekenaar se klankkaart loop nooit op presies dieselfde klok nie; oor ure of dae kan 'n klein verskil geleidelik opbou tot 'n merkbare vertraging (bv. 2 minute) op die FM-uitsending, en 'n herbegin van die rekenaar stel dit weer op nul. Om dit te voorkom word elke netwerkstroom deur 'n begrensde skok-buffer gestuur ("Maksimum stroom-buffer" - instelbaar via Instellings of `radioctl set STREAM_BUFFER_MAX <sekondes>`): sodra die buffer die ingestelde maksimum oorskry, laat Liquidsoap outomaties 'n bietjie oudio val om weer by te kom, i.p.v. dat die vertraging onbeperk bly opbou.

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
radioctl dash           Bring die beheerpaneel-skerm terug (bv. ná 'n shell-escape)
radioctl status         Wys status van al die dienste, sender naam en stroom URL
radioctl start          Begin die radio-diens
radioctl stop           Stop die radio-diens
radioctl restart        Herbegin die radio-diens
radioctl logs [-f]      Wys onlangse logs (-f om te volg)
radioctl test-stream    Toets of die stroom URL bereikbaar is
radioctl media          Wys File Browser toegangsbesonderhede
radioctl backup         Skep 'n rugsteun van die mediavouer
radioctl monitor-url    Wys die netwerk-URL om die op-lug mengsel te monitor
radioctl bufferstat     Wys die regstreekse netwerk-buffer van die aktiewe bron
radioctl datausage      Wys data-verbruik vandag/hierdie maand (vnstat)
radioctl sysstats       Wys CPU-las, geheue, skyfspasie en CPU-temperatuur
radioctl set <S> <W>    Verander 'n instelling (STREAM_URL, BACKUP_STREAM_URL, MUSIC_WEIGHT,
                        SWEEPER_WEIGHT, ALSA_DEVICE, STATION_NAME, HEARTBEAT_URL,
                        STREAM_BUFFER_MAX)
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

Die skerm se opskrif wys die gekonfigureerde sender naam as 'n groot bloklettter-baniere met 'n 3D-skaduwee-effek (via `toilet`, outomaties aangepas by die terminaal se breedte — val terug na gewone teks op klein skerms), en die res van die skerm pas ook outomaties by die terminaal se grootte aan. Die STATUS-afdeling wys `radioctl status`-inligting (aktiewe bron, totale aanlyn-tyd) plus stelsel-inligting wat elke verversing regstreeks bygewerk word — netwerk-buffer, data-verbruik vandag/hierdie maand, CPU-las, geheue en CPU-temperatuur. Vanaf die skerm: `[S]` begin, `[T]` stop, `[R]` herbegin, `[L]` logs, `[P]` monitor aan/af, `[M]` media-besonderhede, `[B]` rugsteun, `[I]` instellings, `[G]` gevaarlike opsies, `[Q]` verlaat na 'n gewone shell. Die opdrag-opsies staan in netjiese, belynde kolomme wat ook by die skermbreedte aanpas. 'n Lewendige ON AIR-aanduiding, watter bron werklik op-lug is, en 'n klankvlak-balk wys reg op dieselfde skerm — daar's geen aparte venster of oorname van die terminaal nie, en elke reël word individueel skoongemaak sodat 'n korter nuwe status (bv. "loop nie" na "loop") nooit stert-karakters van 'n vorige, langer reël agterlaat nie.

### Volskerm op die fisiese skerm

Die Linux-teks-konsole (tty1) gebruik gewoonlik 'n groot verstek-lettertipe wat op 'n breë monitor net 'n klein deel van die skerm benut. Wanneer die beheerpaneel-skerm geïnstalleer word, stel die installer outomaties 'n baie kleiner konsole-lettertipe in (Terminus 12x6), sodat aansienlik meer kolomme en reëls op dieselfde fisiese skerm pas — die dashboard se bestaande aanpas-logika (hierbo) benut dit outomaties, sonder verdere opstelling.

As die skerm steeds nie die volle breedte benut nie (raar op moderne hardeware, maar moontlik as die konsole nie op die skerm se volle native resolusie loop nie), kan 'n GRUB-kernparameter dit regstel — pas die resolusie by jou eie skerm aan:

```bash
sudo nano /etc/default/grub
# Voeg by GRUB_CMDLINE_LINUX_DEFAULT, bv:
#   GRUB_CMDLINE_LINUX_DEFAULT="video=1920x1080@60"
sudo update-grub
sudo reboot
```

Om die lettertipe self weer te verander (groter/kleiner), gebruik `sudo dpkg-reconfigure console-setup`.

### Monitor

`[P]` speel presies dieselfde klank wat na die aux/ALSA-uitset gaan (stroom óf noodmusiek, wat ook al werklik op-lug is) plaaslik via `mpv`, met 'n klankvlak-balk wat regstreeks op die dashboard opdateer. Druk `[P]` weer om te stop (doelbewus anders benoem en gekleur as `[T]` Stop, wat die werklike uitsending stop). (`radioctl monitor-url` gee die onderliggende netwerk-URL indien jy dit elders, bv. in 'n blaaiser, wil oopmaak.)

### Instellings

INSTELLINGS en GEVAARLIK leef altyd op die hoofskerm — geen aparte skerm, oortjies of muisklik meer nie. `[I]` vou die INSTELLINGS-opsies reg op dieselfde skerm oop/toe, en `[G]` doen dieselfde vir GEVAARLIK:

* **INSTELLINGS** (`[I]`) — stroom URL (primêr en rugsteun), stasienaam, ALSA-klanktoestel, musiek/sweeper-verhouding, Heartbeat URL, maksimum stroom-buffer, kleurskema, sagteware-opdatering, herkonfigurasie
* **GEVAARLIK** (`[G]`) — wagwoorde wys, of die hele installasie verwyder (met bevestiging)

Elke opsie is genommer (bv. `1) Stroom URL`); tik die nommer en druk Enter om dit te verander. Al die "verander"-opsies word dadelik toegepas en herbegin die diens waar nodig. Dieselfde instellings is ook direk via `radioctl set <SLEUTEL> <WAARDE>` verstelbaar (bv. `sudo radioctl set BACKUP_STREAM_URL "https://..."`, of `sudo radioctl set HEARTBEAT_URL ""` om dit af te skakel).

Dit werk deur 'n klein plaaslike Icecast-aftakking wat Liquidsoap direk voed (`output.icecast`) — dieselfde reeds-berekende mengsel word bloot ook daarheen gestuur. Die regstreekse netwerk-buffer en data-verbruik-syfers vereis onderskeidelik 'n plaaslike Liquidsoap-beheersocket (`socat`, slegs plaaslik bereikbaar - geen netwerk-poort nie) en `vnstat` — albei word saam met die beheerpaneel-skerm geïnstalleer.

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
