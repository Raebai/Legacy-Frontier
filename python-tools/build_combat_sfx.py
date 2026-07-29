"""Mine the local `Effects/` sound library into the game's shipping SFX roster.

    python python-tools/build_combat_sfx.py            # build everything
    python python-tools/build_combat_sfx.py ice_ earth_  # only keys with these prefixes
    python python-tools/build_combat_sfx.py --dry       # plan + sizes, write nothing

WHY A SCRIPT AND NOT A HAND-COPY.
`Effects/` is a 2 GB, 773-file, gitignored LOCAL library (the Sonniss #GameAudioGDC
bundle plus two free packs). It cannot ship. What ships is a small, deliberate
selection copied into godot-project/assets/audio/sfx/. Doing that by hand would
leave no record of WHICH source file became WHICH game sound, and that record is
the whole value: when the maker says "the shatter is wrong", the fix starts with
knowing it came from Kopeikin's `ice, block of ice crushed, heavy-015.wav` at the
peak transient, not with re-auditioning 773 files.

So the MANIFEST below IS the documentation. Every game sound names its source.

WHAT HAPPENS TO EACH FILE.
  * TomMusic clips are copied VERBATIM as .ogg. They are already 44.1 kHz,
    game-length, and Vorbis -- reprocessing them would only cost quality and
    weight (the .ogg is smaller than a mono 16-bit WAV of the same clip).
  * Everything else is CONVERTED: mono, 44.1 kHz, 16-bit, windowed to the useful
    moment, faded at both edges, peak-normalised to 0.9. The premium packs ship
    96 kHz / 24-bit / stereo masters up to 100 MB; carrying that into a git repo
    for a 2D game would be indefensible.

FINDING THE MOMENT WITHOUT EARS. Nobody can listen to any of this. Three window
modes stand in for listening, and each one is honest about what it assumes:
  * "onset" (default) -- strip leading silence, take `dur` from there. Correct for
    a one-shot library file, which is the common case.
  * "peak"  -- locate the loudest 100 ms window in the WHOLE file and cut around
    it. This is how a thunder crack is found inside seven minutes of rain, or the
    single usable transient inside a two-minute drone.
  * "peak:N" -- the Nth loudest NON-OVERLAPPING transient. Several premium files
    are multi-take reels (the David Dumais swing pack is 68 s of consecutive
    takes); this pulls genuinely different variants out of one file instead of
    two windows of the same hit.
  * a number -- an explicit offset in seconds, when the file's structure is known
    from its own name (e.g. a "whoosh -> impact" designed transition).

CONFIDENCE. Filename, folder, duration and file size are the only evidence
available. Per-entry `sure=` records how much that evidence is worth: HIGH means
the filename says exactly what the game needs it for, LOW means it is a
considered guess the maker should expect to re-point. Run with --dry to print
the confidence breakdown.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import wavkit  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "Effects"
OUT = ROOT / "godot-project" / "assets" / "audio" / "sfx"

# ---------------------------------------------------------------------------
# Pack roots. Short handles keep the manifest readable; the full names are the
# folder names inside Effects/ verbatim.
# ---------------------------------------------------------------------------
TM = "Free Fantasy SFX Pack By TomMusic/OGG Files/SFX"
PEP = "Pepper Sound Pack/Pepper Sound Pack"
KICE = "Alexander Kopeikin - 100 kHz Designed Ice"
KMAG = "Alexander Kopeikin - Emotion and Magic"
COLOSS = "Cinematic Sound Design - Colossal Impacts"
ULTRA = "Cinematic Sound Design - Ultra Transitions & Impacts"
BOOM = "Federico Soler - Effective Trailer Booms Vol. 2"
ALARM = "Federico Soler - Effective Trailer Alarms Vol. 2"
DDU = "David Dumais Audio - Melee Weapons Sound Effects Pack 2"
HC4 = ("Epic Stock Media - Humanoid Creatures Vol 4 - Monstrous and Undead "
       "Creature Vocalization Sound Sets")
TDG = "Epic Stock Media - Tower Defense Game"
SNLS = "Epic Stock Media - Synthesized Nature Loops and Sounds"
SGA3 = "Epic Stock Media - Strange Game Ambient Loops 3"
CB = "CB_Sounddesign - Applicable Sounds - Organic UI and Building Games SFX"
CUI = "Cinematic Sound Design - User Interface"
CSYS = "Cinematic Sound Design - System & UI Feedback Elements"
CINT = "Cinematic Sound Design - Interface & Infographics"
CHYB = "Cinematic Sound Design - Hybrid Game & UI Elements"
CIMP = "Cinematic Sound Design - Cartoon Impacts"
CAN2 = "Cinematic Sound Design - Cartoon & Animation Vol 2"
CDRN = "Cinematic Sound Design - Sci-Fi Drones"
CUIX = "Cinematic Sound Design - UI Interaction Elements"
STORM = ("Epic Stock Media - Public Spaces - Storms Lakes Parks and Rural "
         "Nature Exteriors")
HDLM = "Epic Stock Media - HD Lock And Mechanism Sound Design Kit"
# CC0 files fetched from OpenGameArt to fill gaps the local library genuinely
# cannot -- see godot-project/assets/audio/CREDITS.md for per-file provenance.
# Staged inside Effects/, which is gitignored, so the SOURCES never enter the
# repo; only the processed clips do, exactly like every local pack.
CC0 = "_cc0_downloads"

HIGH, MED, LOW = "HIGH", "MED", "LOW"

# Sample rate for content whose energy is all low-frequency: trailer booms, the
# sub/rumble layer stems, thunder. 22.05 kHz reproduces everything up to 11 kHz,
# and there is nothing above that in a sub-bass boom worth half the file size.
# Everything else stays at 44.1 kHz because transient sparkle -- ice cracking,
# a whip snap, glass -- lives exactly where a low rate would eat it.
LOW_RATE = 22050


def S(pack: str, name: str, dur: float = 0.9, at: str | float = "onset",
      pre: float = 0.03, db: float = 0.0, sure: str = MED,
      rate: int = wavkit.TARGET_RATE, copy: bool = False) -> dict:
    """One source clip. `at`/`pre`/`dur` describe the window; see module docstring.

    `copy=True` ships the source byte-for-byte -- used for the few already-small,
    already-game-length .ogg files where any processing would only cost quality
    (and the stdlib cannot decode Vorbis anyway).
    """
    return {"pack": pack, "name": name, "dur": dur, "at": at, "pre": pre,
            "db": db, "sure": sure, "rate": rate, "copy": copy}


def O(name: str, sure: str = HIGH) -> dict:
    """A TomMusic .ogg copied verbatim -- no window, no processing."""
    return {"pack": TM, "name": name, "copy": True, "sure": sure}


# ---------------------------------------------------------------------------
# THE MANIFEST -- key -> ordered variants. Output files are <key>_<n>.<ext>.
#
# Read this as the answer to "what does each spell actually sound like now".
# ---------------------------------------------------------------------------
MANIFEST: dict[str, list[dict]] = {

    # ===================================================================== CAST
    # A cast is a PROCESS in this game (windup -> sigil -> discharge), so the
    # cast voice is per-ELEMENT rather than one generic "magic" noise.
    "cast_fire": [O("Spells/Fireball 1.ogg"), O("Spells/Fireball 2.ogg"),
                  O("Spells/Fireball 3.ogg")],
    "cast_ice": [O("Spells/Ice Throw 1.ogg"), O("Spells/Ice Throw 2.ogg")],
    "cast_earth": [O("Spells/Rock Meteor Throw 1.ogg"),
                   O("Spells/Rock Meteor Throw 2.ogg")],
    # No shadow spell exists in any pack. Kopeikin's "evil presence, onslaught"
    # is the closest designed intent in the whole library.
    "cast_shadow": [S(KMAG, "magic, action gesture, evil presence, onslaught-004.wav",
                      dur=1.3, at="peak", sure=MED),
                    S(ULTRA, "Transition Braam Slow Dark Creepy.wav",
                      dur=1.4, sure=MED, rate=LOW_RATE)],
    # HOLY WAS THE OTHER REAL GAP. No pack here has a choir, a chime swell or
    # anything angelic; the nearest local material is UI twinkle, which reads as a
    # menu, not a god. `24.wav` is a CC0 vibraphone arpeggio with a trailing
    # triplet echo -- the closest licence-safe thing to a divine chime that exists.
    "cast_holy": [S(CC0, "24.wav", dur=1.4, sure=MED),
                  S(CB, "GAMEMisc_Magic Creation 23_CB Sounddesign_APPlicable Sounds.wav",
                    dur=1.2, sure=MED)],
    "cast_arcane": [S(KMAG, "magic, energy flow, astonishment-001.wav",
                      dur=1.2, sure=HIGH),
                    S(CC0, "magical_1_0.ogg", copy=True, sure=HIGH),
                    S(CC0, "magical_5_0.ogg", copy=True, sure=HIGH)],
    # Storm has no designed source locally -- water spray is the nearest
    # broadband "lashing" texture. Flagged LOW; the online electricity clip is
    # the intended replacement.
    "cast_storm": [S(CC0, "electricspell2.ogg", copy=True, sure=HIGH),
                   S(CC0, "crackleelectricityloop.wav", dur=0.5, sure=HIGH)],

    # The pre-ult swell. Trailer alarm risers are literally built for this beat.
    "charge_ult": [S(ALARM, "EffectiveTrailer_Alarms_Vol2_WholeNotes_011.wav",
                     dur=2.0, sure=MED, rate=LOW_RATE),
                   S(ALARM, "EffectiveTrailer_Alarms_Vol2_HalfNotes_003.wav",
                     dur=2.0, sure=MED, rate=LOW_RATE)],
    # The sigil drawing itself along the aim -- small bright metal taps.
    "sigil_form": [S(SGA3, "MAGShim_Shimmer Loop Small Bell Metal Taps_ESM_SGA3.wav",
                     dur=1.1, at="peak", sure=MED),
                   S(CC0, "magical_3_0.ogg", copy=True, sure=HIGH)],
    # The caster leaving the floor. A tonal drone rising under the windup.
    "levitate": [S(KMAG, "magic, drone, tension, spellbound, evanescence-002.wav",
                   dur=1.8, at="peak", sure=MED, rate=LOW_RATE)],

    # ==================================================================== BEAMS
    # Five beams that were all one `beam` key. Each gets its own voice.
    "beam_arcane": [O("Spells/Firespray 1.ogg"), O("Spells/Firespray 2.ogg")],
    # Frostpiercer -- the thinnest, longest beam. A cracking ice field IS the
    # sound of something tearing along a line.
    "beam_frost": [S(KICE, "ice, surface cracking, fissure, fast, hard-003.wav",
                     dur=1.6, sure=HIGH),
                   S(KICE, "ice, movement, ice drift, ice field cracking up, "
                           "initial, wide-001.wav", dur=1.8, at="peak", sure=MED)],
    # Infernal Lance -- the fattest. Firespray with a real burn under it.
    "beam_fire": [S(SNLS, "FIREBurn_Loop Elements Fire Crackling Crunchy Flame "
                          "Burn 03_ESM_SNLS.wav", dur=1.6, at="peak", sure=MED),
                  O("Spells/Firespray 2.ogg", sure=MED)],
    "beam_shadow": [S(KMAG, "magic, action gesture, evil presence, onslaught-004.wav",
                      dur=1.6, at="peak:2", sure=MED),
                    S(CDRN, "Psycho Glitched Screechy Tones Noise.wav",
                      dur=1.4, at="peak", db=-3.0, sure=LOW, rate=LOW_RATE)],
    "beam_storm": [S(CC0, "electricspell.ogg", copy=True, sure=HIGH),
                   S(SNLS, "WINDInt_Loop Weather Wind Whipping Constricted Flow "
                           "Turbulent 01_ESM_SNLS.wav", dur=1.4, at="peak", sure=LOW)],
    # The frame the beam fires on, and the frame it stops. Layered UNDER the beam
    # body by the mix so a screen-crossing line has an attack and a cut-off.
    "beam_start": [S(ULTRA, "Impact Hit Rapid Chord Reverb.wav", dur=0.9, sure=MED)],
    "beam_end": [S(ULTRA, "Woosh Sweep Slide Infographics Basic.wav",
                   dur=0.7, sure=MED)],

    # ====================================================================== ICE
    # One `ice` key was serving a wall, a spike line, a rime freeze and a shatter.
    "ice_wall": [O("Spells/Ice Wall 1.ogg"), O("Spells/Ice Wall 2.ogg")],
    # Glacial Spine -- a crest ERUPTING from the floor and racing outward. It
    # needs a travelling sound, so it is built from a fissure running through ice
    # rather than from a one-shot impact.
    "ice_spine": [S(KICE, "ice, surface cracking, fissure, fast, hard-003.wav",
                    dur=1.4, at="peak", sure=HIGH),
                  S(KICE, "ice, movement, ice drift, ice field cracking up, "
                          "initial, wide-001.wav", dur=1.5, at="peak:3", sure=MED)],
    "ice_throw": [O("Spells/Ice Throw 1.ogg"), O("Spells/Ice Throw 2.ogg")],
    # Blizzard beat 1: rime ACCRETING on a body. A small repeating tick that
    # rises -- the meter filling. Short and dry on purpose.
    "rime_tick": [S(KICE, "ice, crack, ice block snapping-001.wav",
                    dur=0.3, at="peak", db=-4.0, sure=MED),
                  S(KICE, "ice, crack, ice block snapping-001.wav",
                    dur=0.3, at="peak:2", db=-4.0, sure=MED),
                  S(KICE, "ice, crack, ice block snapping-001.wav",
                    dur=0.3, at="peak:3", db=-4.0, sure=MED)],
    # Blizzard beat 2: ENCASE. The moment it closes over them.
    "ice_encase": [O("Spells/Ice Freeze 1.ogg"), O("Spells/Ice Freeze 2.ogg"),
                   S(TDG, "ICEBrk_Skill Freeze Whoosh Break Impact Layered "
                          "Movement Shatter 03_ESM_TDG.wav", dur=1.0, sure=HIGH)],
    # Blizzard beat 3: SHATTER. The payoff. Real crushed ice, not a pitched-up wall.
    "ice_shatter": [S(KICE, "ice, block of ice crushed, heavy-015.wav",
                      dur=1.1, sure=HIGH),
                    S(TDG, "ICEBrk_Skill Freeze Whoosh Break Impact Layered "
                           "Movement Shatter 03_ESM_TDG.wav", dur=1.2, at="peak",
                      sure=HIGH)],
    "frost_field": [O("Spells/Ice Barrage 1.ogg"), O("Spells/Ice Barrage 2.ogg")],

    # ==================================================================== EARTH
    "earth_wall": [O("Spells/Rock Wall 1.ogg"), O("Spells/Rock Wall 2.ogg")],
    # Colossus Pillar -- a titanic spire slamming down. The single biggest
    # designed impact in the library, with a trailer boom for the low end.
    "earth_pillar": [S(COLOSS, "Impact Cut Sweep.wav", dur=2.0, sure=HIGH),
                     S(BOOM, "EffectiveTrailer_Booms_Vol2_011.wav",
                       dur=2.0, sure=MED, rate=LOW_RATE)],
    "earth_hurl": [O("Spells/Rock Meteor Throw 1.ogg"),
                   O("Spells/Rock Meteor Throw 2.ogg")],
    "earth_impact": [O("Spells/Rock Meteor Swarm 1.ogg"),
                     O("Spells/Rock Meteor Swarm 2.ogg")],
    # Avalanche is a NEAR-SIMULTANEOUS cluster, so it wants the swarm clip plus
    # tumbling debris, not one big hit.
    "avalanche": [O("Spells/Rock Meteor Swarm 2.ogg"),
                  S(COLOSS, "Woosh Debris.wav", dur=2.0, sure=HIGH)],
    "rubble": [S(COLOSS, "Woosh Debris.wav", dur=1.2, at="peak", sure=HIGH),
               S(PEP, "FIGHTING/body_dirt3.wav", dur=1.0, sure=MED)],

    # ================================================================ LIGHTNING
    # THE LIBRARY'S ONE GENUINE HOLE. 773 files across 45 packs and not a single
    # designed electric arc -- TomMusic's fantasy pack has no lightning spell,
    # Pepper is a brawl library, and the premium samplers are ice/impact/boom.
    # This is the gap that justified going online; everything here is CC0.
    "zap": [S(CC0, "spark.wav", dur=0.3, sure=HIGH),
            S(CC0, "groundhit.wav", dur=0.3, sure=HIGH),
            S(CC0, "crackleelectricityloop.wav", dur=0.5, sure=HIGH)],
    "zap_arc": [S(CC0, "spark.wav", dur=0.3, sure=HIGH),
                S(CC0, "crackleelectricityloop.wav", dur=0.5, sure=HIGH)],
    # A chain hop is the SAME arc, shorter and drier -- one link of the leap.
    "zap_chain": [S(CC0, "groundhit.wav", dur=0.3, sure=HIGH),
                  S(CC0, "spark.wav", dur=0.2, at="peak", sure=HIGH)],
    # Thunder: a real close crack, plus a trailer boom for the rolling tail.
    # Low-rate on both -- there is nothing above 11 kHz in either.
    "thunder": [S(CC0, "sfx100v2_thunder_01.ogg", copy=True, sure=HIGH),
                S(STORM, "STORM_Texas Rain Thunder Initial Crash Boom Storm 01 "
                         "Clap Lightning_ESM_CPS.wav", dur=2.0, at="peak",
                  pre=0.12, sure=MED, rate=LOW_RATE),
                S(BOOM, "EffectiveTrailer_Booms_Vol2_214.wav", dur=2.0, sure=MED,
                  rate=LOW_RATE)],

    # =================================================================== SHADOW
    "shadow_cast": [S(KMAG, "magic, action gesture, evil presence, onslaught-004.wav",
                      dur=1.2, sure=MED)],
    # Shadow Crawler comes from UNDER you -- a low tonal creep, not an impact.
    "shadow_crawl": [S(KMAG, "magic, drone, tension, spellbound, evanescence-002.wav",
                       dur=1.4, at="peak:2", sure=MED, rate=LOW_RATE),
                     S(CIMP, "Cartoon Airy Impact Creaks.wav", dur=1.2, sure=LOW)],
    # Shadow Root grabs and holds. Creaks plus something biting into flesh.
    "shadow_root": [S(CIMP, "Cartoon Airy Impact Creaks.wav", dur=1.0, at="peak",
                      sure=MED),
                    S(PEP, "FIGHTING/ImpaleFlesh4.wav", dur=0.8, sure=MED)],
    "void_pull": [S(CAN2, "Cartoon Transition Bass Down.wav", dur=1.6, sure=MED, rate=LOW_RATE),
                  S(KMAG, "magic, energy flow, astral travel-015.wav",
                    dur=1.6, at="peak", sure=LOW, rate=LOW_RATE)],
    # A tear in space. Thin, wrong, and glitched -- deliberately not "big".
    "rift_open": [S(CDRN, "Psycho Glitched Screechy Tones Noise.wav",
                    dur=1.0, at="peak:2", sure=LOW, rate=LOW_RATE),
                  S(CIMP, "Vibrato Impact Snap Spin Transition.wav",
                    dur=1.0, sure=MED)],

    # ===================================================================== HOLY
    "holy_swell": [S(CC0, "24.wav", dur=1.8, at="peak", sure=MED),
                   S(CSYS, "Interface Arp Reveal Down Long.wav", dur=1.6, sure=LOW)],
    # Judgment -- a single holy pillar landing.
    "holy_pillar": [S(BOOM, "EffectiveTrailer_Booms_Vol2_214.wav", dur=2.0, sure=MED, rate=LOW_RATE),
                    S(COLOSS, "Impact Cut Sweep.wav", dur=2.0, at="peak", sure=MED)],
    # Heaven's Verdict beat 1: a HAIRLINE thread appears. Tense, thin, quiet.
    "verdict_thread": [S(ALARM, "EffectiveTrailer_Alarms_Vol2_QuarterNotes_013.wav",
                         dur=1.8, db=-3.0, sure=MED, rate=LOW_RATE)],
    # Beat 2: the burn-down.
    "verdict_burn": [S(BOOM, "EffectiveTrailer_Booms_Vol2_075.wav", dur=2.0, sure=MED, rate=LOW_RATE)],
    # Aegis Ward. Three separate beats the game currently plays as one `ding`.
    "ward_raise": [S(CINT, "Interface Accept Glassy Snap.wav", dur=0.9, sure=MED),
                   S(CC0, "24.wav", dur=1.0, at="peak:2", sure=MED)],
    # ABSORB is not BREAK: the ward eats the spell and survives. A muted, swallowed
    # "deny" -- the deliberate opposite of a shatter.
    "ward_absorb": [S(CSYS, "Interface Deny Low Fat Dark.wav", dur=0.9, sure=HIGH),
                    S(CUIX, "Deny Muted.wav", dur=0.9, sure=HIGH)],
    # One rune plate cracking. Glass, not ice.
    "ward_crack": [S(CC0, "sfx100v2_glass_02.ogg", copy=True, sure=HIGH),
                   S(KICE, "ice, crack, ice block snapping-001.wav",
                     dur=0.7, at="peak:4", sure=MED)],
    "ward_break": [S(CC0, "sfx100v2_glass_05.ogg", copy=True, sure=HIGH),
                   S(KICE, "ice, block of ice crushed, heavy-015.wav",
                     dur=1.2, at="peak", sure=MED),
                   S(TDG, "ICEBrk_Skill Freeze Whoosh Break Impact Layered "
                          "Movement Shatter 03_ESM_TDG.wav", dur=1.2, at="peak:2",
                     sure=MED)],

    # ===================================================================== ULTS
    # The ults are now deliberately distinct EVENTS, so they stop sharing `cannon`.
    "ult_siege": [S(ALARM, "EffectiveTrailer_Alarms_Vol2_HalfNotes_003.wav",
                    dur=2.0, at="peak", sure=MED, rate=LOW_RATE),
                  S(ULTRA, "Transition Braam Slow Dark Creepy.wav", dur=2.0, sure=MED, rate=LOW_RATE)],
    "ult_bombardment": [S(COLOSS, "Woosh Debris.wav", dur=2.0, sure=HIGH),
                        O("Spells/Rock Meteor Swarm 1.ogg", sure=MED)],
    "ult_eruption": [S(BOOM, "EffectiveTrailer_Booms_Vol2_011.wav",
                       dur=2.0, at="peak", sure=MED, rate=LOW_RATE),
                     S(COLOSS, "Transition Frantic Shaker Snap.wav", dur=2.0, sure=MED)],
    "ult_avalanche": [O("Spells/Rock Meteor Swarm 1.ogg", sure=HIGH),
                      S(COLOSS, "Woosh Debris.wav", dur=2.0, at="peak", sure=HIGH)],
    # A floor-hugging shove -- a sweep that stays low, not a detonation.
    "ult_shove": [S(ULTRA, "Woosh Sweep Slide Infographics Basic.wav",
                    dur=1.2, sure=MED),
                  S(CAN2, "Cartoon Transition Bass Down.wav", dur=1.6, at="peak",
                    sure=MED, rate=LOW_RATE)],
    # UNMAKING. Its audio identity is ABSENCE. This is deliberately the quietest
    # entry in the roster and the mix trims it further -- see Sfx.PROFILE. It must
    # register as "the sound stopped", not as another explosion.
    "ult_unmaking": [S(CDRN, "Psycho Glitched Screechy Tones Noise.wav",
                       dur=1.4, at="peak:4", db=-9.0, sure=LOW, rate=LOW_RATE)],
    # Hollow Purple: intake, then the erasure lance.
    "hollow_intake": [S(CAN2, "Cartoon Transition Bass Down.wav", dur=1.8, sure=MED, rate=LOW_RATE),
                      S(KMAG, "magic, energy flow, astral travel-015.wav",
                        dur=1.8, at="peak:2", sure=LOW, rate=LOW_RATE)],
    "hollow_erase": [S(BOOM, "EffectiveTrailer_Booms_Vol2_011.wav",
                       dur=2.0, sure=MED, rate=LOW_RATE),
                     S(ULTRA, "Impact Hit Rapid Chord Reverb.wav", dur=2.0,
                       at="peak", sure=MED)],

    # ============================================================= DRAIN TETHER
    # A hooked whip that LASHES, bites, drains, and can be TORN free. The library
    # has a literal whip pack, which is the single best filename match in it.
    "whip_lash": [S(DDU, "WEAPWhip_WHIP Snap Crack 05_DDUMAIS_MWP2.wav",
                    dur=0.8, at="peak", sure=HIGH),
                  S(DDU, "WEAPWhip_WHIP Snap Crack 05_DDUMAIS_MWP2.wav",
                    dur=0.8, at="peak:2", sure=HIGH),
                  S(DDU, "WEAPWhip_WHIP Snap Crack 05_DDUMAIS_MWP2.wav",
                    dur=0.8, at="peak:3", sure=HIGH)],
    "whip_bite": [S(PEP, "FIGHTING/ImpaleFlesh1.wav", dur=0.8, sure=HIGH),
                  S(PEP, "FIGHTING/ImpaleFlesh6.wav", dur=0.8, sure=HIGH)],
    "drain_pull": [S(KMAG, "magic, energy flow, astral travel-015.wav",
                     dur=1.4, at="peak:3", sure=LOW, rate=LOW_RATE),
                   S(KMAG, "magic, energy flow, astonishment-001.wav",
                     dur=1.4, at="peak", sure=MED)],
    # The line under tension letting go.
    "tether_tear": [S(DDU, "WEAPWhip_WHIP Snap Crack 05_DDUMAIS_MWP2.wav",
                      dur=0.7, at="peak:4", sure=MED),
                    S(PEP, "BLOOD/crunch enhancer 03.wav", dur=0.7, sure=MED)],
    "whip_miss": [S(PEP, "FIGHTING/sfx_whoosh_lo03.wav", dur=0.6, sure=HIGH),
                  S(PEP, "FIGHTING/sfx_whoosh_lo05.wav", dur=0.6, sure=HIGH)],

    # ============================================================ MELEE / CLASH
    # REMAPPED. `melee_swing` and `melee_hit` used TomMusic's sword clips, which
    # are a fantasy-RPG sword, not a stick figure throwing hands. Pepper's
    # FIGHTING folder is a dedicated 142-file brawl library.
    "melee_swing": [S(PEP, "FIGHTING/sfx_whoosh_hi01.wav", dur=0.5, sure=HIGH),
                    S(PEP, "FIGHTING/sfx_whoosh_hi03.wav", dur=0.5, sure=HIGH),
                    S(PEP, "FIGHTING/Arm Whoosh Quick 02.wav", dur=0.5, sure=HIGH),
                    S(PEP, "FIGHTING/sfx_whoosh_hi05.wav", dur=0.5, sure=HIGH)],
    "melee_swing_heavy": [S(PEP, "FIGHTING/sfx_whoosh_lo01.wav", dur=0.7, sure=HIGH),
                          S(PEP, "FIGHTING/sfx_whoosh_lo04.wav", dur=0.7, sure=HIGH),
                          S(DDU, "METLFric_SWING SCRAPE Swift Melee Weapon Swing "
                                 "With A Long Blade 14_DDUMAIS_MWP2.wav",
                            dur=0.8, at="peak", sure=HIGH)],
    "melee_hit": [S(PEP, "FIGHTING/sfx_hit_body01.wav", dur=0.5, sure=HIGH),
                  S(PEP, "FIGHTING/sfx_hit_body03.wav", dur=0.5, sure=HIGH),
                  S(PEP, "FIGHTING/KungFu OldSchool Hit2.wav", dur=0.5, sure=HIGH),
                  S(PEP, "FIGHTING/sfx_hit_body04.wav", dur=0.5, sure=HIGH)],
    "melee_hit_heavy": [S(PEP, "BLOOD/big_hardpunch2.wav", dur=0.8, sure=HIGH),
                        S(PEP, "BLOOD/big_hardpunch5.wav", dur=0.8, sure=HIGH),
                        S(PEP, "FIGHTING/hard enhancer 03.wav", dur=0.8, sure=HIGH)],
    "melee_crit": [S(PEP, "FIGHTING/sfx_hit_face_lg01.wav", dur=0.9, sure=HIGH),
                   S(PEP, "FIGHTING/sfx_hit_face_lg03.wav", dur=0.9, sure=HIGH)],
    # THE CLASH -- two blows meeting. Requested by the melee-clash agent. A block
    # transient plus a resonant metal ring, so it reads as a MEETING rather than
    # as either fighter landing a hit.
    "clash": [S(PEP, "FIGHTING/sfx_hit_block_lg01.wav", dur=0.6, sure=HIGH),
              S(PEP, "FIGHTING/sfx_hit_block_lg03.wav", dur=0.6, sure=HIGH),
              O("Attacks/Sword Attacks Hits and Blocks/Sword Blocked 2.ogg", sure=HIGH)],
    "clash_heavy": [S(DDU, "METLImpt_METAL SWING HIT Weapon Swing To Metallic Body "
                           "Impact And Resonant Tail 01_DDUMAIS_MWP2.wav",
                      dur=1.4, at="peak", sure=HIGH),
                    S(PEP, "FIGHTING/hard enhancer 01.wav", dur=1.0, sure=MED)],
    "parry": [O("Attacks/Sword Attacks Hits and Blocks/Sword Parry 1.ogg"),
              O("Attacks/Sword Attacks Hits and Blocks/Sword Parry 2.ogg"),
              O("Attacks/Sword Attacks Hits and Blocks/Sword Parry 3.ogg")],
    "block": [S(PEP, "FIGHTING/sfx_hit_block_lg02.wav", dur=0.6, sure=HIGH),
              S(PEP, "FIGHTING/sfx_hit_block_lg04.wav", dur=0.6, sure=HIGH)],
    "guard_break": [S(PEP, "BLOOD/crunch enhancer 01.wav", dur=0.9, sure=MED),
                    S(PEP, "FIGHTING/hard enhancer 04.wav", dur=0.9, sure=MED)],
    "punch": [S(PEP, "FIGHTING/punch19.wav", dur=0.5, sure=HIGH),
              S(PEP, "FIGHTING/punch_h_05.wav", dur=0.5, sure=HIGH),
              S(PEP, "FIGHTING/punch20.wav", dur=0.5, sure=HIGH)],
    "kick": [S(PEP, "FIGHTING/kick type3 02.wav", dur=0.6, sure=HIGH),
             S(PEP, "FIGHTING/kick type3 05.wav", dur=0.6, sure=HIGH)],

    # ================================================================ REACTIONS
    # Spell-vs-spell outcomes. These had NO sounds at all and are exactly the
    # "cinematic" moments. Names match ReactionTable's outcome keys 1:1 so the
    # reactions agent can wire them without a lookup table.
    "rx_steam": [S(SNLS, "FIREBurn_Loop Elements Fire Crackling Crunchy Flame "
                         "Burn 03_ESM_SNLS.wav", dur=1.4, at="peak", sure=MED),
                 O("Spells/Waterspray 2.ogg", sure=MED)],
    "rx_supercharge": [S(CC0, "crackleelectricityloop.wav", dur=0.5, sure=HIGH),
                       S(ULTRA, "Impact Hit Rapid Chord Reverb.wav", dur=1.4,
                         sure=MED)],
    "rx_shatter": [S(KICE, "ice, block of ice crushed, heavy-015.wav",
                     dur=1.0, at="peak:2", sure=HIGH),
                   S(KICE, "ice, crack, ice block snapping-001.wav",
                     dur=0.9, at="peak:5", sure=HIGH)],
    # Shrapnel is a CONE of fragments, not one break: a fissure plus gore-grade
    # debris texture.
    "rx_shrapnel": [S(KICE, "ice, surface cracking, fissure, fast, hard-003.wav",
                      dur=1.0, at="peak:2", sure=MED),
                    S(PEP, "BLOOD/gore enhancer 04.wav", dur=0.9, sure=MED)],
    "rx_void_pull": [S(CAN2, "Cartoon Transition Bass Down.wav",
                       dur=1.4, at="peak", sure=MED, rate=LOW_RATE)],
    "rx_resonance": [S(ULTRA, "Impact Hit Rapid Chord Reverb.wav",
                       dur=1.8, at="peak", sure=HIGH)],
    "rx_carve": [S(DDU, "METLFric_SWING SCRAPE Swift Melee Weapon Swing With A "
                        "Long Blade 14_DDUMAIS_MWP2.wav", dur=1.0, at="peak:2",
                   sure=HIGH),
                 S(KICE, "ice, surface cracking, fissure, fast, hard-003.wav",
                   dur=1.0, at="peak:3", sure=MED)],
    "rx_annihilate": [S(BOOM, "EffectiveTrailer_Booms_Vol2_011.wav",
                        dur=2.0, at="peak:2", sure=MED, rate=LOW_RATE),
                      S(COLOSS, "Impact Cut Sweep.wav", dur=2.0, at="peak:2",
                        sure=MED)],
    "rx_breach": [S(COLOSS, "Transition Frantic Shaker Snap.wav", dur=1.4, sure=MED),
                  O("Spells/Rock Wall 2.ogg", sure=MED)],
    "rx_ward_absorb": [S(CUIX, "Deny Muted.wav", dur=0.9, at="peak", sure=HIGH),
                       S(CSYS, "Interface Deny Low Fat Dark.wav", dur=0.9,
                         at="peak", sure=HIGH)],
    "rx_overpower": [S(BOOM, "EffectiveTrailer_Booms_Vol2_075.wav",
                       dur=2.0, at="peak", sure=MED, rate=LOW_RATE)],
    "rx_ground_out": [S(CSYS, "Interface Sci-Fi Ping Down.wav", dur=1.0, sure=MED),
                      S(TDG, "ROBTMvmt_Tower Deploy Hitech Robot Motor Dark Thump "
                             "Servo Whine 04_ESM_TDG.wav", dur=1.0, sure=LOW)],
    "rx_field_merge": [S(KMAG, "magic, drone, tension, spellbound, "
                               "evanescence-002.wav", dur=1.6, at="peak:3",
                         sure=MED, rate=LOW_RATE)],
    # BANISH -- holy light burning a shadow field out of existence. Not an impact
    # and not a shatter: something is being ERASED, so it is a bright swell plus a
    # dispersal, and the two sources here are used nowhere else in the roster so
    # it cannot be mistaken for any other holy cue.
    "rx_banish": [S(CB, "UIMisc_Xylophone Ringtone 2_CB Sounddesign_APPlicable "
                        "Sounds.wav", dur=1.6, at="peak", sure=MED),
                  S(CHYB, "Cofetti Whoosh Pluck Spill.wav", dur=1.4, sure=MED)],
    "rx_blocked": [S(PEP, "FIGHTING/sfx_hit_block_lg02.wav", dur=0.6, sure=HIGH),
                   O("Attacks/Sword Attacks Hits and Blocks/Sword Blocked 3.ogg",
                     sure=HIGH)],

    # =================================================================== BODIES
    # REMAPPED. `enemy_death` and `hero_hurt` were synth placeholders. There is a
    # dedicated creature-vocalisation pack and a 45-file body-damage folder here.
    "enemy_death": [S(HC4, "VOXReac_Construction Kit Male Flutter Death Vocal "
                           "Stuttered Long 05_ESM_HC4.wav", dur=1.4, sure=HIGH),
                    S(HC4, "CREAMnstr_Designed Sea Beast Creature Pain Intense "
                           "Yell Long 04_ESM_HC4.wav", dur=1.4, at="peak", sure=HIGH),
                    S(PEP, "BLOOD/Explode_Bod3.wav", dur=1.0, sure=MED)],
    "enemy_death_big": [S(PEP, "MONSTER/GiantMonster_02.wav", dur=1.6, sure=HIGH),
                        S(PEP, "MONSTER/GiantMonster_04.wav", dur=1.6, sure=HIGH)],
    "enemy_hurt": [S(HC4, "HMNBrth_Construction Kit Male Screeching Breath Inhale "
                          "Weak Squeal 05_ESM_HC4.wav", dur=0.9, sure=HIGH),
                   S(PEP, "BLOOD/damage3.wav", dur=0.9, sure=HIGH),
                   S(PEP, "BLOOD/damage6.wav", dur=0.9, sure=HIGH)],
    "hero_hurt": [S(PEP, "FIGHTING/damage_h2.wav", dur=0.9, sure=HIGH),
                  S(PEP, "FIGHTING/damage_h5.wav", dur=0.9, sure=HIGH),
                  S(PEP, "FIGHTING/damage_h7.wav", dur=0.9, sure=HIGH)],
    # A ragdoll hitting the floor -- the rig flops constantly and had no sound.
    "body_fall": [S(PEP, "FIGHTING/body_ground1.wav", dur=1.0, sure=HIGH),
                  S(PEP, "FIGHTING/body_fall2.wav", dur=1.0, sure=HIGH),
                  S(PEP, "FIGHTING/body_dirt2.wav", dur=1.0, sure=HIGH)],
    "gib": [S(PEP, "BLOOD/gib.wav", dur=0.8, sure=HIGH),
            S(PEP, "BLOOD/Explode_Bod5.wav", dur=1.0, sure=HIGH)],

    # ========================================================== MOVEMENT, WORLD
    "dash": [S(PEP, "FIGHTING/sfx_whoosh_lo_sh01.wav", dur=0.5, sure=HIGH),
             S(PEP, "FIGHTING/sfx_whoosh_lo_sh04.wav", dur=0.5, sure=HIGH)],
    # REMAPPED from synth blips to real recorded footfalls on rock.
    "step": [S(PEP, "FOOTSTEPS/run_rock_1.wav", dur=0.3, sure=HIGH),
             S(PEP, "FOOTSTEPS/run_rock_2.wav", dur=0.3, sure=HIGH),
             S(PEP, "FOOTSTEPS/run_rock_3.wav", dur=0.3, sure=HIGH),
             S(PEP, "FOOTSTEPS/run_rock_4.wav", dur=0.3, sure=HIGH)],
    "land": [S(PEP, "FOOTSTEPS/land_rock.wav", dur=0.8, sure=HIGH),
             S(PEP, "FOOTSTEPS/land_ground.wav", dur=0.8, sure=HIGH)],
    "crate_break": [O("Chopping and Mining/chop 1.ogg", sure=MED),
                    S(PEP, "FIGHTING/body_wood1.wav", dur=0.9, sure=MED)],
    "platform_break": [O("Chopping and Mining/mine 3.ogg", sure=MED),
                       S(COLOSS, "Transition Frantic Shaker Snap.wav",
                         dur=1.4, at="peak", sure=MED)],
    # The "something bad is coming" tell on a telegraphed enemy attack.
    "telegraph": [S(ALARM, "EffectiveTrailer_Alarms_Vol2_QuarterNotes_013.wav",
                    dur=1.2, sure=HIGH, rate=LOW_RATE),
                  S(CSYS, "Interface Sci-Fi Ping Down.wav", dur=0.9, at="peak",
                    sure=MED)],

    # ==================================================================== STEMS
    # The automatic layer stems. `sub_boom` was synthesised; a real trailer boom
    # is a categorically better low end and it is the layer that decides whether
    # anything in this game feels heavy.
    "sub_boom": [S(BOOM, "EffectiveTrailer_Booms_Vol2_075.wav", dur=1.8, sure=HIGH, rate=LOW_RATE),
                 S(BOOM, "EffectiveTrailer_Booms_Vol2_214.wav", dur=1.8, at="peak",
                   sure=HIGH, rate=LOW_RATE)],
    "rumble": [S(BOOM, "EffectiveTrailer_Booms_Vol2_011.wav", dur=2.0, at="peak:3",
                 sure=MED, rate=LOW_RATE),
               S(CDRN, "Dark Industrial Ambience.wav", dur=2.0, at="peak", sure=LOW, rate=LOW_RATE)],
    "crack": [S(CINT, "Interface Percussion Snap.wav", dur=0.4, sure=HIGH),
              S(PEP, "FIGHTING/thud2.wav", dur=0.4, sure=HIGH)],
}


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def find_peaks(samples: list[float], rate: int, n: int,
               win_s: float = 0.10) -> list[int]:
    """The `n` loudest NON-OVERLAPPING transients, loudest first.

    Several premium sources are multi-take reels rather than single one-shots
    (the David Dumais swing file is 68 s of consecutive takes). Blanking a
    window around each pick before the next search is what makes "peak:2" a
    genuinely different hit instead of a second slice of the same one.
    """
    win = max(1, int(rate * win_s))
    guard = win * 6  # ~0.6 s of separation between accepted picks
    work = list(samples)
    picks: list[int] = []
    for _ in range(n):
        idx = wavkit.find_peak_window(work, rate, win_s)
        picks.append(idx)
        lo, hi = max(0, idx - guard), min(len(work), idx + guard)
        for j in range(lo, hi):
            work[j] = 0.0
    return picks


def resolve_window(samples: list[float], rate: int, spec: dict) -> int:
    at = spec["at"]
    if isinstance(at, (int, float)):
        return max(0, int(float(at) * rate))
    if at == "onset":
        return wavkit.find_onset(samples, rate)
    if at == "peak":
        return max(0, wavkit.find_peak_window(samples, rate))
    if at.startswith("peak:"):
        n = int(at.split(":", 1)[1])
        return max(0, find_peaks(samples, rate, n)[n - 1])
    raise ValueError(f"unknown window spec {at!r}")


def build(prefixes: list[str], dry: bool) -> None:
    total = 0
    rows: list[tuple[str, str, int, str]] = []
    conf = {HIGH: 0, MED: 0, LOW: 0}
    cache: dict[str, tuple[list[float], int]] = {}

    for key, variants in MANIFEST.items():
        if prefixes and not any(key.startswith(p) for p in prefixes):
            continue
        for i, spec in enumerate(variants, start=1):
            src = LIB / spec["pack"] / spec["name"]
            conf[spec["sure"]] += 1
            if not src.exists():
                print(f"  MISSING SOURCE  {key}_{i}: {src}")
                continue

            if spec.get("copy"):
                dst = OUT / f"{key}_{i}{src.suffix}"
                size = src.stat().st_size
                if not dry:
                    shutil.copyfile(src, dst)
            else:
                dst = OUT / f"{key}_{i}.wav"
                ck = str(src)
                if ck not in cache:
                    cache[ck] = wavkit.read_mono(src)
                samples, rate = cache[ck]
                start = resolve_window(samples, rate, spec)
                start = max(0, start - int(spec["pre"] * rate))
                clip = samples[start:start + int(spec["dur"] * rate)]
                if not clip:
                    print(f"  EMPTY WINDOW    {key}_{i}: {src.name}")
                    continue
                out_rate: int = int(spec["rate"])
                clip = wavkit.resample(clip, rate, out_rate)
                clip = wavkit.normalise(clip)
                clip = wavkit.gain_db(clip, spec["db"])
                # 4 ms in / 30 ms out. The in-fade only kills the DC step at the
                # cut; the out-fade has to be long enough to hide a mid-waveform
                # truncation but short enough not to soften a transient tail.
                clip = wavkit.fade(clip, out_rate, 0.004, 0.030)
                size = ((len(clip) * 2) + 44 if dry
                        else wavkit.write_wav16(dst, clip, out_rate))

            total += size
            rows.append((dst.name, f"{spec['pack']}/{spec['name']}", size,
                         spec["sure"]))
        # Long sources are 30-100 MB decoded to float lists; hold at most one.
        if len(cache) > 2:
            cache.clear()

    for name, src, size, sure in rows:
        print(f"{size:>9,}  {sure:<4}  {name:<26}  <- {src}")
    print(f"\n{len(rows)} files, {total:,} bytes ({total / 1048576:.2f} MiB)")
    print(f"confidence: HIGH {conf[HIGH]}  MED {conf[MED]}  LOW {conf[LOW]}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    build(args, "--dry" in sys.argv)
