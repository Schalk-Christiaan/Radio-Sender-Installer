# Radio Orania Sender Installer

'n Eenvoudige Debian-gebaseerde installer vir afgeleë radiosenders.

## Doel

Hierdie projek installeer en konfigureer 'n volledige Radio Orania sender op Debian 13.

Die sender speel 'n internetstroom af en skakel outomaties oor na noodmusiek indien die stroom wegval.

## Funksies

* Liquidsoap radiosender
* Outomatiese stroom-monitering
* Noodmusiek en sweepers
* ALSA klankuitset
* Systemd dienste
* Heartbeat ondersteuning
* File Browser vir media bestuur
* Outomatiese installasie en validasie

## Hoe dit werk

```text
Internet Stroom
       │
       ▼
  Liquidsoap
       │
       ├─ Stroom beskikbaar
       │        │
       │        ▼
       │      ALSA
       │
       └─ Stroom af
                │
                ▼
      Musiek + Sweepers
                │
                ▼
              ALSA
```

## Media Bestuur

Media word bestuur deur File Browser:

```text
/opt/radio-orania/media
├── Musiek
└── Sweepers
```

## Installasie

Kloon die repository:

```bash
git clone https://github.com/Schalk-Christiaan/Radio-Sender-Installer.git
```

Gaan na die projek gids:

```bash
cd Radio-Sender-Installer
```

Begin die installer:

```bash
sudo bash install.sh
```

Die installer sal jou vra vir:

* Sender naam
* Stroom URL
* ALSA toestel
* Musiek gewig
* Sweeper gewig
* Heartbeat URL (opsioneel)
* File Browser instellings

Na installasie sal die stelsel outomaties:

* Liquidsoap konfigureer
* Systemd dienste registreer
* Media gidse skep
* File Browser opstel
* Die installasie valideer

## Gids Struktuur

```text
/opt/radio-orania
├── config
├── liquidsoap
├── logs
├── monitoring
├── filebrowser
└── media
    ├── Musiek
    └── Sweepers
```

## Projek Status

Aktief ontwikkel vir Radio Orania.

Fokus:

* Betroubaarheid
* Eenvoud
* Maklike ontplooiing
* Min handmatige konfigurasie
* Volledig oopbron
