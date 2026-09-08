
# Plaaslike beheer-koppelvlak (Unix-socket)
#
# Word slegs geaktiveer wanneer die dashboard geïnstalleer is. Laat die
# dashboard toe om regstreekse metrieke (bv. radio_input.buffer_length) by
# Liquidsoap te bevraagteken via 'n plaaslike lêer-socket - nie 'n
# netwerk-poort nie, so dit is nie op afstand bereikbaar nie. Sien
# templates/radioctl.sh (cmd_bufferstat) vir die bevraagteker.

settings.server.socket := true
settings.server.socket.path := "/opt/radio-orania/liquidsoap/socket"
