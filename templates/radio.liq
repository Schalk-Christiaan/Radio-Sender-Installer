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

# Hoeveel sekondes stilte (op die lewendige stroom) toegelaat word voor
# blank.strip() hieronder dit as "af" behandel en na noodmusiek oorskakel -
# te kort, en 'n gewone asemhaal-stiltetjie in 'n gesprek skakel per
# ongeluk reeds oor.
silence_threshold = __SILENCE_THRESHOLD__

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
# ontkoppeling nie. max_blank=silence_threshold (Liquidsoap se eie
# verstek is 20 sekondes) - min_noise=0.0 (verstek) beteken enige geluid
# breek die stilte-telling dadelik weer af, so 'n regte, kort stiltetjie
# tussen sinne by die bron self veroorsaak nie per ongeluk 'n wissel nie.
#
# buffer.adaptative() i.p.v. buffer(): die bron se enkodeerder en die
# klankkaart loop nooit presies teen dieselfde tempo nie. Die gewone
# buffer() het daardie klok-verskil hanteer deur by oorloop 'n stuk oudio
# te laat val (en by leegloop kortliks na noodmusiek te wissel) - albei
# hoorbaar as 'n "spring" in die klank. buffer.adaptative() versnel/vertraag
# die afspeel onhoorbaar min sodat die buffervlak konstant bly. max= begrens
# steeds die vertraging, sodat dit nie oor dae tot 'n merkbare FM-vertraging
# opbou nie.

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
# knip.

def crossfade(old, new) =
  add(normalize=false, [fade.out(duration=2.0, old), fade.in(duration=2.0, new)])
end

# Bronkeuse-lys: (naam, predikaat, bron). Die ENIGSTE plek waar bronkeuse
# beskryf word - switch() hieronder en check_active_source() (wat die
# dashboard/radioctl/notify se "Bron"-veld voed) word albei hieruit afgelei,
# so die twee kan nie uit-pas raak nie. Die naam is wat na die
# active_source-lêer geskryf word.

switch_sources =
  [
    ("primer", {source_override() == "primer" and radio_connected()}, radio),
    ("noodmusiek", {source_override() == "noodmusiek"}, backup_program),
    ("primer", {source_override() == "" and primary_source == "1" and radio_connected()}, radio),
# __PRIMARY_SOURCE_SWITCH_BACKUP_BRANCH__
    ("noodmusiek", {true}, backup_program)
  ]

def switch_entry(entry) =
  let (_, pred, src) = entry
  (pred, src)
end

main =
  switch(
    track_sensitive=false,
    transitions=list.map(fun (_) -> crossfade, switch_sources),
    list.map(switch_entry, switch_sources)
  )

# Klankvlak-egalisering, sodat die stroom en plaaslike musiek nie skielik
# harder/sagter as mekaar klink nie.

main = normalize(main)

# ALSA uitset
#
# Die ALSA-uitset bepaal die klok van die hele hoofketting. Niks anders mag
# dit ophou nie - die Icecast-monitor (indien geïnstalleer) loop daarom op
# sy eie klok agter 'n buffer() (sien radio-icecast.liq).

output.alsa(
  device=alsa_device,
  main
)

# Aktiewe-bron opsporing
#
# Skryf elke 2 sekondes na 'n lêer watter bron werklik op-lug is: die
# eerste inskrywing in switch_sources waarvan die predikaat waar is EN die
# bron gereed is - presies wat switch() self doen. (Die is_ready()-toets is
# nodig: tydens 'n buffer-leegloop speel switch() reeds noodmusiek terwyl
# radio_connected() nog waar is.)

def pick_active(acc, entry) =
  let (name, pred, src) = entry
  if acc == "" and pred() and src.is_ready() then name else acc end
end

def check_active_source()
  file.write(
    data=list.fold(pick_active, "", switch_sources),
    atomic=true,
    temp_dir="/opt/radio-orania/liquidsoap",
    "/opt/radio-orania/liquidsoap/active_source"
  )
  2.0
end

thread.run.recurrent(delay=2.0, check_active_source)
