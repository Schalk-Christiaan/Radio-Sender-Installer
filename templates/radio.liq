# Instellings

radio_url = "__STREAM_URL__"

music_folder = "/opt/radio-orania/emergency/Musiek"

sweeper_folder = "/opt/radio-orania/emergency/Sweepers"

music_weight = __MUSIC_WEIGHT__
sweeper_weight = __SWEEPER_WEIGHT__

playlist_reload = __PLAYLIST_RELOAD__
playlist_prefetch = __PLAYLIST_PREFETCH__

alsa_device = "__ALSA_DEVICE__"

# Radio.co stroom

radio =
  mksafe(
    input.http(
      self_sync=false,
      radio_url
    )
  )


# Noodmusiek

emergency_music =
  playlist(
    id="Musiek",
    mode="randomize",
    reload=playlist_reload,
    reload_mode="seconds",
    prefetch=playlist_prefetch,
    music_folder
  )


# Sweepers

sweepers =
  playlist(
    id="Sweepers",
    mode="random",
    sweeper_folder
  )


# Backup program

backup_program =
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



# Hoof bron

main =
  fallback(
    track_sensitive=false,
    [
      radio,
      backup_program
    ]
  )


# Klank uitset

output.alsa(
  device=alsa_device,
  main
)
