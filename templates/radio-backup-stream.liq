
# Rugsteun-stroom
#
# Word gebruik as die hoofstroom afgaan (of stil raak) voor daar na
# plaaslike musiek/sweepers oorgeskakel word.

backup_radio_url = "__BACKUP_STREAM_URL__"

backup_radio =
  blank.strip(
    input.http(
      self_sync=false,
      backup_radio_url
    )
  )
