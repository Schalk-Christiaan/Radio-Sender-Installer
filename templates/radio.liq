# Instellings

settings.init.allow_root := true

radio_url = "https://stream.radio.co/s7adaa782c/listen"

music_folder = "/opt/radio-orania/media/Musiek"

sweeper_folder = "/opt/radio-orania/media/Sweepers"

music_weight = 4
sweeper_weight = 1

playlist_reload = 1000
playlist_prefetch = 10

alsa_device = "default"


# Radio stroom

radio =
  input.http(
    self_sync=false,
    radio_url
  )

# Musiek

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
  mksafe(
    fallback(
      track_sensitive=false,
      [
        radio,
        backup_program
      ]
    )
  )

# ALSA uitset

output.alsa(
  device=alsa_device,
  main
)
