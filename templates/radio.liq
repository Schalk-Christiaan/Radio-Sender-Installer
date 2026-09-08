# Instellings

radio_url = "__STREAM_URL__"

music_folder = "/opt/radio-orania/media/Musiek"

sweeper_folder = "/opt/radio-orania/media/Sweepers"

music_weight = __MUSIC_WEIGHT__
sweeper_weight = __SWEEPER_WEIGHT__

playlist_reload = __PLAYLIST_RELOAD__
playlist_prefetch = __PLAYLIST_PREFETCH__

alsa_device = "__ALSA_DEVICE__"

stream_buffer_max = __STREAM_BUFFER_MAX__

# Radio stroom
#
# blank.strip maak die bron "onbeskikbaar" sodra dit stil raak, al bly
# die HTTP-koppeling tegnies gekoppel - só skakel fallback() ook oor by
# "dooie lug" (bv. 'n koderfout by die bron), nie net by 'n werklike
# ontkoppeling nie.
#
# buffer() met 'n begrensde max= voorkom dat 'n klein klok-verskil tussen
# die netwerkstroom en die klankkaart oor ure/dae onbeperk opbou tot 'n
# merkbare FM-vertraging - sodra die buffer die maksimum oorskry, laat
# Liquidsoap outomaties 'n bietjie oudio val om weer by te kom, i.p.v. dat
# net 'n herbegin van die rekenaar dit regstel.

radio =
  buffer(
    max=stream_buffer_max,
    blank.strip(
      input.http(
        self_sync=false,
        id="radio_input",
        radio_url
      )
    )
  )

# __BACKUP_RADIO_INSERT_POINT__

# Musiek

emergency_music =
  mksafe(
    playlist(
      mode="random",
      music_folder
    )
  )

# Sweepers

sweepers =
  mksafe(
    playlist(
      mode="random",
      sweeper_folder
    )
  )

# Backup program

backup_program =
  mksafe(
    rotate(
      weights=[
        music_weight,
        sweeper_weight
      ],
      [
        emergency_music,
        sweepers
      ]
    )
  )

# Hoof bron

main =
  fallback(
    track_sensitive=false,
    [
      radio,
      __BACKUP_RADIO_ENTRY__
      backup_program
    ]
  )

# Klankvlak-egalisering, sodat die stroom en plaaslike musiek nie skielik
# harder/sagter as mekaar klink nie.

main = normalize(main)

# ALSA uitset

output.alsa(
  device=alsa_device,
  main
)

# Aktiewe-bron opsporing
#
# Skryf elke 2 sekondes na 'n lêer watter bron werklik op-lug is, met
# dieselfde volgorde-logika as die fallback() hierbo - radioctl en die
# dashboard lees hierdie lêer om die aktiewe bron te wys sonder om
# Liquidsoap self te moet bevraagteken.

def check_active_source()
  active =
    if radio.is_ready() then
      "primer"
# __ACTIVE_SOURCE_BACKUP_BRANCH__
    else
      "noodmusiek"
    end
  file.write(
    data=active,
    atomic=true,
    temp_dir="/opt/radio-orania/liquidsoap",
    "/opt/radio-orania/liquidsoap/active_source"
  )
  2.0
end

thread.run.recurrent(delay=2.0, check_active_source)
