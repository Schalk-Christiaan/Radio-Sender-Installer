
# Monitor-aftakking (Icecast)
#
# Stuur presies dieselfde klank wat na die aux/ALSA-uitset gaan (stroom óf
# noodmusiek, wat ook al werklik op-lug is) ook na 'n plaaslike Icecast-
# aftakking, sodat 'n operateur dit oor die netwerk kan monitor.

output.icecast(
  %mp3(bitrate=128),
  host="localhost",
  port=__ICECAST_PORT__,
  password="__ICECAST_SOURCE_PASSWORD__",
  mount="monitor",
  main
)
