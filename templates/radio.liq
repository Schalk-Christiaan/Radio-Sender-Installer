# Instellings

radio_url = "__STREAM_URL__"

music_folder = "/opt/radio-orania/media/Musiek"

sweeper_folder = "/opt/radio-orania/media/Sweepers"

music_weight = __MUSIC_WEIGHT__
sweeper_weight = __SWEEPER_WEIGHT__

playlist_reload = __PLAYLIST_RELOAD__
playlist_prefetch = __PLAYLIST_PREFETCH__

alsa_device = "__ALSA_DEVICE__"

# Radio stroom
#
# blank.strip maak die bron "onbeskikbaar" sodra dit stil raak, al bly
# die HTTP-koppeling tegnies gekoppel - só skakel fallback() ook oor by
# "dooie lug" (bv. 'n koderfout by die bron), nie net by 'n werklike
# ontkoppeling nie.

radio =
  blank.strip(
    input.http(
      self_sync=false,
      radio_url
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
