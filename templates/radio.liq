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

# Watter bron by verstek (geen handmatige wissel aktief nie) eerste
# probeer word: "1" verkies die hoofstroom, "2" die rugsteunstroom. Word
# net "2" as 'n rugsteunstroom ook geconfigureer is - radioctl valideer
# dit by "set".
primary_source = "__PRIMARY_SOURCE__"

# Lêer waarin 'n handmatige bron-oorheersing (radioctl wissel) gestoor
# word: "primer", "rugsteun", "noodmusiek", of leeg vir outomaties. Word
# by elke diens-begin teruggestel na leeg, sodat 'n vergete wissel nie
# oor 'n herbegin/herlaai heen bly vassit nie.
source_override_path = "/opt/radio-orania/liquidsoap/source_override"

file.write(
  data="",
  atomic=true,
  temp_dir="/opt/radio-orania/liquidsoap",
  source_override_path
)

source_override = ref("")

def read_source_override()
  source_override := (
    if file.exists(source_override_path) then
      string.trim(file.contents(source_override_path))
    else
      ""
    end
  )
  2.0
end

thread.run.recurrent(delay=2.0, read_source_override)

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
#
# switch() se predikate is doelbewus onderling uitsluitend gehou (elkeen
# noem net een source_override()/primary_source-kombinasie), sodat hul
# volgorde in die lys nie die uitkoms verander nie, behalwe waar dit
# doelbewus 'n voorkeur-kaskade beskryf (bv. primer eers, dan rugsteun,
# by dieselfde primary_source-waarde). switch() slaan self reeds 'n tak
# oor as sy bron nie gereed is nie (soos fallback() ook doen), so 'n
# geforseerde bron wat afgaan val steeds outomaties verder - na musiek
# toe, doelbewus nie na die ánder stroom nie, want 'n eksplisiete keuse
# vir een stroom moet nie stilweg na die ander omruil nie.

main =
  switch(
    track_sensitive=false,
    [
      ({source_override() == "primer"}, radio),
      ({source_override() == "noodmusiek"}, backup_program),
      ({source_override() == "" and primary_source == "1"}, radio),
# __PRIMARY_SOURCE_SWITCH_BACKUP_BRANCH__
      ({true}, backup_program)
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
# dieselfde volgorde-logika as die switch() hierbo - moet by enige
# wysiging aan die switch()-predikate saam opgedateer word, anders raak
# die status-kaart se "Bron"-veld uit-pas met wat werklik speel.
# radioctl en die dashboard lees hierdie lêer om die aktiewe bron te
# wys sonder om Liquidsoap self te moet bevraagteken.

def check_active_source()
  active =
    if source_override() == "primer" and radio.is_ready() then
      "primer"
    elsif source_override() == "noodmusiek" then
      "noodmusiek"
    elsif source_override() == "" and primary_source == "1" and radio.is_ready() then
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
