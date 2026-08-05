# LIVE PLAYTEST QUEUE — 2026-08-05 (wave 3)

The maker calls things out faster than they can be built. Verbatim intent preserved.
**Nothing here is a design question — it is all "make it so".**

> Read `docs/NEXT-SESSION.md` for the root causes and the measurements.

---

## ✅ DONE THIS ROUND

- **"The deflect and that logic implemented as intended."** MEASURED 2 → 13 deflects
  across 18 duels. `BotDodge` answered a vertical dodge-exit with a JUMP and returned
  before the parry rung below it — and a horizontal bolt between two grounded fighters
  yields a vertical exit *every frame*, so parry was only reachable while airborne.
  Plus: the two most common deflect paths played the ding with no hitstop or camera
  kick, and `guard_style` meant two different things across the seam.
- **"Bots deflect here and there, dash away as needed."** Same fix. The parry only wins
  inside each class's own timing band, so the body still jumps for everything else.
- **1v1 BOT MATCHES READY TO SHARE.** The clip pipeline had two silent lies — it was
  encoding frames from **before the app rename**, and it played at **~3x fast-forward**.
  Plus the strobe that blanked both fighters, the 6%-of-frame-height framing, the
  2.8-seconds-of-frozen-still tail, and the winner's health bar sitting on the winner.
- **"Remove that impossible wording at the top of the screen."** Gone from the clock,
  and from the VS card where it appeared twice.
- **"Two defaults hit each other → fizzle out."** Head-on bolts now pop each other.
  Guarded by a `require_head_on` predicate so ranged mirror matches stay winnable.
- **"Brawler punching a spell."** `Spell.gd` was the ONLY projectile in the game
  without `consume()` — a fist could smash a hurled boulder and phase through a bolt.
- **"The ice class needs a buff."** Independently confirmed: Cryomancer measured **25%**
  over 72 bouts, second worst. HP 123 → 152.
- **"Lightning should be little particles on the user, not that large circle thing;
  same with frozen and burnt."** They were discs drawn at the BODY origin, which sits
  at mid-thigh — a ring the figure stood *inside*. Now drawn by the rig, on the limbs.
- **"The spell slots are kinda boring."** Seven flat black rectangles under a screen
  full of rotating magic circles. Now dashed circles that turn, cooldown = the ring
  closing, no numerals.
- **"The sword hit has a white sphere on it."** HDR white flash blooming a stick
  figure's head circle. Now a red flash, matching the hero.
- **"The Warden is all messed up."** An ignored `.tscn` header attribute put every
  townsperson on the rig's own ground mask. Legs measured **0.09 px**.
- **"Swordsaint should move faster and dash longer."** Travel 57.6 → 106.4 px.
- **FLOOR 2** — the blocker. Fixed, plus the missing kill plane that turned it from a
  hiccup into an unrecoverable soft-lock.
- **There was no in-game route to a bot fight at all** — `Lobby._watch_bots` had zero
  callers. The button is back.

---

## ✅ DONE SINCE (2026-08-05 c)

- **"More bosses / mini-bosses."** Roster 4 → 6: **THE ERASER** (floors 1-6, eats
  the room, the answer is to come close and stay) and **THE ETCHER** (3+, its
  biggest cast can be INTERRUPTED, and the acid pool under its own feet is the
  price of getting close enough to do it). Measured: distinct artists per climb
  3.7/4 → 4.99/6, Guardian repeats 3.3 → 2.3, deep pool 3 → 4.
- **Mini-bosses.** Not new bodies — a **wave slot**. Floors 3, 7 and 9 now spend
  their whole elite budget inside ONE named wave instead of sprinkling it across
  forty bodies. ⚠ It concentrates; it does not stage into an emptied room. Two
  deliberate invariants blocked that and they are yours to revisit.
- **"The spell slots are kinda boring"** (the rest of it). Colour and tier could
  not separate four slots, so each socket now carries a FIGURE — the same
  thirteen the cast circles use. 24 of 36 hands used to show a duplicate; now 0.
- **Ordinary enemies casting spells** — landed in the previous round (`1de8f5c`).
- **Gravity flip** — landed in the previous round; it is a WELL you move inside,
  and the caster is excluded on your ruling.

## ✅ DONE SINCE (2026-08-05 e)

- **The scorches were still perfect circles.** The ground pass toned them and never
  tore them, so the large smooth pale discs on the floor were those, not the craters.
  Torn now, same `_ragged` treatment, verified before and after at the same crop.
- **The elemental weapon trail, seen at last.** Confirmed taking the aura branch
  (orange against a blue limb colour) on a fire Brawler. It is DIM on a dark floor —
  dials named in `NEXT-SESSION.md`, and the call is yours.
- **The time-stop bubble on the real arena.** Bounded (ratio 1.18 = `BUBBLE_SCALE`)
  and it reads BRIGHT, not dark — **there is no pale arena sky**; all ten biome
  washes are dark. Both of the warnings attached to this item were wrong.

## ▶ STILL OPEN

1. **PLAY IT.** Thirty-six commits, none of it touched by hands.
2. **A bigger, more interactive map.**
6. **The ragdoll on hold-down** still wants judging now that the legs are correct.
7. **Balance is a HANDICAP, not a kit fix.** Every matchup is watchable; the kits are
   still uneven. Said out loud rather than papered over.
8. **Nothing has ever touched a touchscreen**, and the audio has still never been heard.
