
# Monitor-aftakking (Icecast)
#
# Stuur presies dieselfde klank wat na die aux/ALSA-uitset gaan (stroom óf
# noodmusiek, wat ook al werklik op-lug is) ook na 'n plaaslike Icecast-
# aftakking, sodat 'n operateur dit oor die netwerk kan monitor.
#
# buffer() plaas die monitor op sy eie klok: 'n haperende/herbeginnende
# Icecast of 'n stadige mp3-enkodeer kan só nooit die ALSA-uitset (FM)
# ophou nie - net die monitor self hik dan. fallible=true omdat die buffer
# kortliks leeg kan wees.

output.icecast(
  %mp3(bitrate=128),
  fallible=true,
  host="localhost",
  port=__ICECAST_PORT__,
  password="__ICECAST_SOURCE_PASSWORD__",
  mount="monitor",
  # adaptative: gewone buffer() het elke ~20 min leeggeloop (klok-drywing
  # tussen ALSA en die monitor) en Icecast herkoppel - nou pas dit spoed aan.
  buffer.adaptative(fallible=true, limit=1.01, averaging=120., main)
)
