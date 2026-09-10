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
#
# Die ongewikkelde (rou) playlist() hieronder hou sy égte gereedheid -
# is_ready() raak vals as die vouer leeg is. mksafe() daarna maak die
# bron "onfeilbaar" (altyd gereed, met stilte as daar niks is nie) sodat
# backup_program altyd 'n geldige laaste-uitweg vir switch() bly. Die
# rou verwysing (emergency_music_raw) word verderaan gebruik om regtig
# leë musiek-/sweeper-vouers op te spoor - sien read_source_override().

emergency_music_raw =
  playlist(
    # "randomize" skommel die hele lys en speel dan daardeur sonder
    # herhaling totdat elke lêer een keer gespeel het (dan skommel dit
    # weer) - "random" (die vorige waarde) trek elke keer heeltemal
    # onafhanklik, wat toegelaat het dat dieselfde liedjie/sweeper
    # dadelik weer agtermekaar speel.
    mode="randomize",
    reload=playlist_reload,
    reload_mode="seconds",
    prefetch=playlist_prefetch,
    music_folder
  )

emergency_music = mksafe(emergency_music_raw)

# Sweepers

sweepers_raw =
  playlist(
    mode="randomize",
    reload=playlist_reload,
    reload_mode="seconds",
    prefetch=playlist_prefetch,
    sweeper_folder
  )

sweepers = mksafe(sweepers_raw)

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

# Bron-oorheersing (radioctl wissel) - lees elke 2 sekondes.
#
# "noodmusiek" word doelbewus verlaag na "" (outomaties) as die
# musiek-/sweeper-vouers werklik leeg is: sonder hierdie kontrole sou
# switch() vaskyk op 'n stil backup_program (mksafe maak dit "gereed"
# ondanks leë vouers), en NOOIT terugval na die lewendige strome toe nie
# - presies die "dooie lug"-toestand wat hierdie hele stelsel juis moet
# voorkom. primer/rugsteun-oorheersings het nie hierdie kontrole nodig
# nie: switch() se ingeboude is_ready()-toets sien reeds self raak as
# 'n regte netwerkstroom afgaan.

source_override = ref("")

def read_source_override()
  requested =
    if file.exists(source_override_path) then
      string.trim(file.contents(source_override_path))
    else
      ""
    end
  source_override := (
    if
      requested == "noodmusiek"
      and not emergency_music_raw.is_ready()
      and not sweepers_raw.is_ready()
    then
      ""
    else
      requested
    end
  )
  2.0
end

thread.run.recurrent(delay=2.0, read_source_override)

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
