
# Rugsteun-stroom
#
# Word gebruik as die hoofstroom afgaan (of stil raak) voor daar na
# plaaslike musiek/sweepers oorgeskakel word.

backup_radio_url = "__BACKUP_STREAM_URL__"

# Sien radio.liq se opmerking by radio_connected hierbo vir waarom
# hierdie nodig is i.p.v. backup_radio.is_ready().
backup_radio_connected = ref(false)

backup_radio =
  buffer(
    max=stream_buffer_max,
    blank.strip(
      input.http(
        self_sync=false,
        id="backup_input",
        on_connect=(fun (headers) -> backup_radio_connected := true),
        on_disconnect={backup_radio_connected := false},
        backup_radio_url
      )
    )
  )
