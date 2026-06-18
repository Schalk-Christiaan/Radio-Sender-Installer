# Radio Sender Installer

'n Eenvoudige Debian-gebaseerde radiosender wat ontwerp is om 'n aanlyn stroom na 'n plaaslike klanktoestel uit te stuur. Indien die stroom wegval, skakel die sender outomaties oor na noodmusiek en sweepers totdat die verbinding herstel is.

## Doel

Die doel van hierdie projek is om die opstelling van radiosenders te standaardiseer en te vereenvoudig.

In plaas daarvan om elke sender handmatig op te stel, installeer hierdie projek al die nodige komponente, skep die vereiste vouers, genereer die konfigurasie en stel die dienste op.

Die einddoel is dat 'n gebruiker slegs een installasie-opdrag hoef uit te voer en dan deur 'n kort opstelproses gelei word.

## Wat die installer doen

Die installer:

* Installeer alle vereiste afhanklikhede
* Installeer Liquidsoap
* Skep die volledige vouerstruktuur
* Genereer die Liquidsoap-konfigurasie
* Stel die systemd diens op
* Installeer heartbeat monitering
* Valideer die installasie
* Berei die sender voor vir Uptime Kuma monitering

## Werking van die Stelsel

```text
                     Internet Stroom
                            │
                            ▼
                     ┌────────────┐
                     │ Liquidsoap │
                     └──────┬─────┘
                            │
            ┌───────────────┴───────────────┐
            │                               │

            ▼                               ▼

      Hoofstroom OK                  Hoofstroom Af
            │                               │
            ▼                               ▼

      Direk na ALSA              Musiek + Sweepers
            │                               │
            └───────────────┬───────────────┘
                            │
                            ▼

                      ALSA Uitset
                            │
                            ▼

                     FM Sender / Mixer
```

## Installasie

Kloon die projek:

```bash
git clone https://github.com/Schalk-Christiaan/Radio-Sender-Installer.git
cd Radio-Sender-Installer
```

Begin die installasie:

```bash
sudo bash install.sh
```

Indien geen konfigurasie bestaan nie, sal die installer outomaties die opstelproses begin.

## Vouerstruktuur

Die volgende struktuur word onder `/opt/radio-sender` geskep:

```text
/opt/radio-sender
│
├── config/
│
├── liquidsoap/
│   └── radio.liq
│
├── emergency/
│   ├── Musiek/
│   └── Sweepers/
│
├── logs/
│
├── heartbeat/
│
├── downloads/
│
├── cache/
│
└── backup/
```

### config

Bevat alle konfigurasielêers wat deur die installer gegenereer word.

### liquidsoap

Bevat die Liquidsoap konfigurasie en senderlogika.

### emergency

Bevat die noodmusiek en sweepers wat gebruik word wanneer die hoofstroom nie beskikbaar is nie.

### logs

Loglêers van die sender en ondersteunende komponente.

### heartbeat

Skripte wat gebruik word vir eksterne monitering.

### downloads

Tydelike aflaaie wat tydens installasie gebruik word.

### cache

Tydelike data wat deur die sender gegenereer word.

### backup

Ruimte vir toekomstige rugsteunfunksies.

## Werkswyse

Die sender probeer voortdurend om die ingestelde stroombron te speel.

Normale vloei:

```text
Internet Stroom
        │
        ▼
    Liquidsoap
        │
        ▼
    ALSA Uitset
```

Indien die stroom wegval:

```text
Internet Stroom
      X

Liquidsoap
      │
      ▼
Noodmusiek
      │
      ▼
Sweepers
      │
      ▼
ALSA Uitset
```

Sodra die stroom weer beskikbaar raak, skakel die sender outomaties terug.

## Monitering

Hierdie projek is ontwerp om saam met Uptime Kuma gebruik te word.

Die sender stuur periodieke heartbeats wat deur 'n afgeleë Uptime Kuma instansie gemonitor kan word.

Dit maak dit moontlik om:

* Senderprobleme op te spoor
* Internetonderbrekings te identifiseer
* Kennisgewings te ontvang indien die sender ophou werk

## Projek Status

Die projek is tans in aktiewe ontwikkeling.

Die fokus is tans op:

* Stabiliteit
* Outomatiese installasie
* Maklike ontplooiing
* Herbruikbaarheid tussen verskillende radiostasies
