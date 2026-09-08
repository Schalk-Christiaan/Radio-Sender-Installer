
# Rugsteun-stroom
#
# Word gebruik as die hoofstroom afgaan (of stil raak) voor daar na
# plaaslike musiek/sweepers oorgeskakel word.

backup_radio_url = "__BACKUP_STREAM_URL__"

backup_radio =
  buffer(
    max=stream_buffer_max,
    blank.strip(
      input.http(
        self_sync=false,
        id="backup_input",
        backup_radio_url
      )
    )
  )
