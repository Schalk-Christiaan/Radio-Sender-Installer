
# Rugsteun-stroom
#
# Word gebruik as die hoofstroom afgaan (of stil raak) voor daar na
# plaaslike musiek/sweepers oorgeskakel word.

backup_radio_url = "__BACKUP_STREAM_URL__"

# Sien radio.liq se opmerking by radio_connected hierbo vir waarom
# hierdie nodig is i.p.v. backup_radio.is_ready().
backup_radio_connected = ref(false)

backup_radio =
  # blank.strip BUITE die buffer: dis 'n aktiewe operator wat die buffer
  # aanhou leeg lees, ook terwyl dit stilte wegsny. Binne die buffer het 'n
  # stilte by die bron die buffer laat leegloop, sodat elke stilte ook 'n
  # buffer-leegloop (en 'n hervul-wag) geword het.
  blank.strip(
    max_blank=silence_threshold,
    buffer.adaptative(
      # fallible: bron mag afgaan (dan wissel switch() oor); reset: begin na
      # elke herkoppeling weer by normale spoed i.p.v. die ou skatting.
      fallible=true,
      reset=true,
      # Vul eers die helfte van die maksimum voor dit (weer) speel: 'n kort
      # netwerk-hik word dan uit die buffer oorbrug i.p.v. 'n wissel na
      # noodmusiek, en na 'n leegloop flikker dit nie elke 2s heen en weer
      # terwyl die verbinding nog sukkel nie (getoets met 3s-onderbrekings
      # en bandwydte onder die stroom se bitkoers).
      buffer=stream_buffer_max / 2.,
      # Spoed-aanpassing hoogstens 1% (verstek 25% - hoorbaar as toonhoogte
      # wat skuif). Klok-drywing tussen bron en klankkaart is ~0.01-0.05%,
      # so 1% is ruim; averaging=120 laat dit kalm i.p.v. ruk-ruk reageer.
      limit=1.01,
      averaging=120.,
      max=stream_buffer_max,
      input.http(
        self_sync=false,
        id="backup_input",
        on_connect=(fun (headers) -> backup_radio_connected := true),
        on_disconnect={backup_radio_connected := false},
        backup_radio_url
      )
    )
  )
