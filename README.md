# Radio Sender Installer

'n Eenvoudige installer vir 'n Linux-gebaseerde radiosender wat 'n internetstroom speel en outomaties na noodmusiek oorskakel wanneer die stroom wegval.

## Werking van die Stelsel

```text
Internet Stroom
       │
       ▼
  Liquidsoap
       │
       ├── Stroom beskikbaar ──► ALSA Uitset
       │
       └── Stroom af
                │
                ▼
        Musiek + Sweepers
                │
                ▼
           ALSA Uitset
                │
                ▼
         Klankkaart / Sender
```

## Wat die Installer Doen

```text
Begin
 │
 ▼
Vra vir Konfigurasie
 │
 ▼
Installeer Afhanklikhede
 │
 ▼
Skep Vouers
 │
 ▼
Bou Liquidsoap Konfigurasie
 │
 ▼
Registreer Dienste
 │
 ▼
Valideer Installasie
 │
 ▼
Gereed
```

## Vouerstruktuur

```text
/opt/radio-orania
├── config
├── liquidsoap
├── logs
├── emergency
│   ├── Musiek
│   └── Sweepers
└── monitoring
```

## Installasie

```bash
curl -O https://raw.githubusercontent.com/Schalk-Christiaan/Radio-Sender-Installer/main/install.sh
sudo bash install.sh
```

## Kenmerke

* Liquidsoap-gebaseerde afspeelstelsel
* Outomatiese noodmusiek
* ALSA klankuitset
* Systemd diens
* Heartbeat monitering
* Uptime Kuma ondersteuning
* Interaktiewe installasie

## Toekoms

* Musiekpakkette vanaf GitHub
* Proxy ondersteuning
* Outomatiese opdaterings
* Verskeie senderprofiele
