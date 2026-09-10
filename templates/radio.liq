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
# ontkoppeling nie. max_blank=3.0 (verstek is 20 sekondes!) verkort die
# hoeveelheid stilte wat 'n luisteraar ooit sou hoor voordat daar
# oorgeskakel word - 'n regte, kort stiltetjie tussen snitte by die
# bron self sal nie per ongeluk 'n wissel veroorsaak nie, want
# min_noise=0.0 (verstek) beteken enige geluid breek die stilte-telling
# dadelik weer af.
#
# buffer() met 'n begrensde max= voorkom dat 'n klein klok-verskil tussen
# die netwerkstroom en die klankkaart oor ure/dae onbeperk opbou tot 'n
# merkbare FM-vertraging - sodra die buffer die maksimum oorskry, laat
# Liquidsoap outomaties 'n bietjie oudio val om weer by te kom, i.p.v. dat
# net 'n herbegin van die rekenaar dit regstel.

# radio.is_ready() (op die buffer()/blank.strip() hieronder) bly
# "gereed" lank nadat die netwerk werklik af is - dit reflekteer net of
# die bron geïnisialiseer is, nie of dit tans gekoppel is nie. Getoets
# en bevestig: tydens 'n volledige verbindingsverlies bly dit tot
# 20-30s "gereed" voordat input.http() self 'n mislukking registreer,
# en daardie mislukking bereik nie is_ready() deur die buffer()-laag
# heen nie. radio_connected hou dus self tred, direk op input.http() se
# eie on_connect/on_disconnect - dís waarop switch() hieronder staatmaak
# om 'n regte ontkoppeling raak te sien, nie radio.is_ready() nie.

radio_connected = ref(false)

radio =
  buffer(
    max=stream_buffer_max,
    blank.strip(
      max_blank=3.0,
      input.http(
        self_sync=false,
        id="radio_input",
        on_connect=(fun (headers) -> radio_connected := true),
        on_disconnect={radio_connected := false},
        radio_url
      )
    )
  )

# __BACKUP_RADIO_INSERT_POINT__

# Musiek
#
# Bly doelbewus ONGEWIKKEL (nie in mksafe() toegedraai nie) - hul
# egte is_ready() (vals as die vouer leeg is) word verderaan gebruik om
# (a) regtig leë musiek-/sweeper-vouers op te spoor (sien
# read_source_override()) en (b) backup_program (hieronder) na die
# ingeboude noodtoon te laat oorskakel as albei werklik leeg is. Die
# mksafe()-waarborg ("altyd gereed") sit op backup_program self, nie
# hier nie.

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

# Sweepers

sweepers_raw =
  playlist(
    mode="randomize",
    reload=playlist_reload,
    reload_mode="seconds",
    prefetch=playlist_prefetch,
    sweeper_folder
  )

# Noodtoon - installeerder se eie ingeboude klank (nie deel van die
# admin se Musiek/Sweepers nie), sodat daar selfs met heeltemal leë
# media-vouers nooit werklike stilte is nie. Word deur scripts/liquidsoap.sh
# eenmalig met ffmpeg gegenereer as dit nog nie bestaan nie.

emergency_fallback_folder = "/opt/radio-orania/liquidsoap/noodklank"

emergency_fallback =
  mksafe(
    playlist(
      mode="randomize",
      emergency_fallback_folder
    )
  )

# Backup program
#
# fallback() (nie mksafe(rotate(...)) direk nie) sodat, as die admin se
# Musiek/Sweepers ALBEI werklik leeg is, dit na die noodtoon oorskakel
# i.p.v. op stilte vas te sit - rotate() self raak nie-gereed wanneer
# al sy tak-bronne (die rou, ongewikkelde verwysings) nie-gereed is.

backup_program =
  mksafe(
    fallback(
      track_sensitive=false,
      [
        rotate(
          weights=[
            music_weight,
            sweeper_weight
          ],
          [
            emergency_music_raw,
            sweepers_raw
          ]
        ),
        emergency_fallback
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

# 'n Skielike knip by elke bronwissel (bv. stroom -> musiek by 'n
# ontkoppeling) klink self soos 'n hoorbare hik. crossfade() oorvloei
# die uitgaande en inkomende bron oor 2 sekondes i.p.v. 'n skielike
# knip. list.map() bou 'n oorvloei-funksie per inskrywing in
# switch_sources hieronder, ongeag hoeveel takke daar (met/sonder
# rugsteunstroom) werklik is - moet dus NIE self met die hand
# opgedateer word as die predikate-lys groei/krimp nie.

def crossfade(old, new) =
  add(normalize=false, [fade.out(duration=2.0, old), fade.in(duration=2.0, new)])
end

switch_sources =
  [
    ({source_override() == "primer" and radio_connected()}, radio),
    ({source_override() == "noodmusiek"}, backup_program),
    ({source_override() == "" and primary_source == "1" and radio_connected()}, radio),
# __PRIMARY_SOURCE_SWITCH_BACKUP_BRANCH__
    ({true}, backup_program)
  ]

main =
  switch(
    track_sensitive=false,
    transitions=list.map(fun (pair) -> crossfade, switch_sources),
    switch_sources
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
    if source_override() == "primer" and radio_connected() then
      "primer"
    elsif source_override() == "noodmusiek" then
      "noodmusiek"
    elsif source_override() == "" and primary_source == "1" and radio_connected() then
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
