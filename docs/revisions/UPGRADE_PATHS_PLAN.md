# Upgrade paths plan: from "functional" to "fully optimized" (draft 3, owner decisions in)

Owner requests (2026-11-14 / 15): every stat starts **functional** and, maxed out, is **fully optimized**; research
first, plan before coding; most upgrades have visual stages, each a new Blender model; Mars only allows so many
paths, so the player must choose and live with it; a new **radiation** stat; **COLONY OVER** with the reason when a
life stat hits zero; **"Press H for help"** with a gold sparkle path; the drone flies like the owner's FPV example;
the rover stays drivable; ores spread across the map, richer further out.

**Draft 2 changes (owner, 2026-11-15):** no build points: **one build a day**. Everything is grouped into **five core
sections** (Energy, Biology, Health, Science, Communication), and each section's upgrades are chosen at **one core
spot**. Water, recycling, food systems and supplies/storage are part of **Biology's food track**. Suits and airlocks
come **with Health's protection track**. The workshop is folded into **Science**. Crew quarters are dropped (§8).
New: **suit radio** rules (§7.1), **ores across the map** (§9), **Mars weather** (§10).

**Draft 3 (owner answers, 2026-11-15):** the nuclear reactor is allowed as a night-power choice; a crewmate at the
radiation limit **gets sick and goes into isolation**; COLONY OVER after a **5-minute countdown**; **H shows the gold
sparkle lines** (the supplies-bar fold moves to U); the crew's day is **strict** (NASA crews follow a fixed
timeline); suit radio starts at a **30 s delay** and shrinks every level; **one build a day for the whole colony**, so
the crew must agree on it, which needs good comms. All decisions are listed in §12.

Research with sources: `docs/revisions/research/` (ores, power, rover and drone, radiation/food/life support,
weather). Owner's drone example: `docs/revisions/reference/fpv_drone/`. Today's code: 8 tracks × 4 levels in
`data/area_levels.json`, costs 2/3/4 spare parts, no choices, no radiation, nothing ends the colony.

---

## 1. Rules for every path

### 1.1 Gold and sparkles mean one thing (constant)
Gold + sparkles = **"this works / this way"**: guide lines, the help path, tapes to find, a fixed part, a finished
upgrade. Nothing else is gold or sparkles (warnings stay red/orange; "you can do this" stays green).

### 1.2 Big jump first, smaller after ("iPhone curve")
Every numeric upgrade gains about **+60 %, then +30 %, then +15 %, then +8 %** over the level before. Later levels
also add a **new ability**, so they never feel pointless. (Li-ion batteries: ~70–120 → 250–300 Wh/kg in 30 years with
shrinking yearly gains.)

### 1.3 One build a day, and choices you live with
- **One build a day for the whole colony.** The colony can finish **one upgrade per sol**, chosen together in the
  evening "Plan" block of the crew's day (§1.7). No points to count. Every crewmate can vote from wherever they are
  only if the comms reach them (§7): crewmates out of radio contact miss the vote, so **good comms matter**.
- **Materials:** each upgrade costs spare parts and ores (iron, silica, regolith, sulfur …) that the drone and rover
  find (§9). The whole map holds enough for about **60 % of all levels**, so nobody maxes everything.
- **Upkeep:** most levels draw a little more power (some use water), so every upgrade makes energy matter more.
- **Forks:** some paths branch (night power: fuel cells **or** a fission reactor; both allowed, owner). Picking one
  locks the other.
- **Permanent:** the confirm card says "This is permanent: you can't take it back. You will be strong at X and still
  weak at Y." No refunds.
- **Colony balance meter:** shows the weakest system (food, air, water, power, radiation, health) and how many crew
  the colony can really support. Maxing one thing while another is weak shows up there at once.

### 1.4 Every visible change is its own Blender model
When an upgrade changes how an object or a room looks, that stage gets **its own Blender file** (exported to a glb):
`blender/upgrades/<section>/<track>_v<n>.blend` → `assets/upgrades/<section>/<track>_v<n>.glb`, built by a script
like the drone's (`tools/blender/drone/build_drone.py`) and checked against the intact map so nothing floats. At least
3 visual stages per track that is a place or a machine; technical-only upgrades (software, schedules) show as icons
and numbers instead.

### 1.5 COLONY OVER
When oxygen, water, food or power reaches zero, a **5-minute countdown** (real time, on screen) starts. If the store is
still at zero when it ends, the colony ends: a full screen "COLONY OVER" with the reason in plain words ("The colony
ran out of oxygen."), the sol, and what would have helped. Getting the store above zero stops the countdown. The colony
also ends when no crewmate can work (all sick in isolation or lost). Warnings first at 25 % and 10 %, then the
countdown.

### 1.6 "Press H for help"
**H always shows the gold sparkle lines** (owner): press H and the same gold sparkle lines as the tape trails appear
from you to what matters now: the emergency, the current goal, or the place your schedule block wants you. A timed
emergency (air leak, power fault, storm …) running past ~60 % of its time pops up **"Press H for help"**, and Mission
Control says what to do. H folding the supplies bar moves to **U**.

### 1.7 The crew's day (short version of the owner's schedule, Appendix A)
**Strict** (owner: NASA crews follow a fixed timeline). One meal block a day stands for breakfast, lunch and dinner;
hygiene and sleep happen on their own; each block is one short task. The HUD shows the current block and where to be
(H draws the sparkle line there). During a block only that block's activities are open, plus emergencies; being
somewhere else gets a "You are late for …" reminder from Mission Control, and a missed block has its cost (no science
from a missed work block, health from missed exercise, a missed vote from a missed Plan block). Crewmates no player
controls follow it by themselves. What the crew use (water, food, air) grows with the number of crewmates. One sol is
20 real minutes by default (the host can set 5–120), so a game hour is about 49 s and the work block about 3.7 min.

| Time | Block | What happens | Gives / uses (per crewmate) |
|---|---|---|---|
| 06:30 | Wake up | automatic: wipes, no showers | **1.5 L water** (owner) |
| 07:00 | **Meal** | mess hall: greens + packed food, heated electrically (no flames); scraps → compost | 1 sol of food; body energy |
| 07:30 | Systems round | each crewmate checks one system: power (panels, batteries), air or water | faults caught early are cheaper |
| 08:00 | **Work block** (by role) | Biologist: plants and experiments. Field engineer/geologist: rocks and dust outside. Electrical engineer: fixes, efficiency. Medic: crew vitals data | science, samples |
| 12:30 | Exercise (required) | treadmill, bike, resistance machine | keeps bone, muscle and heart health |
| 14:30 | Base chores | log data, store a supply drop, laundry, rover care | keeps the base tidy and working |
| 18:00 | Field mission (optional) | rover trip, **at least 2 crew** | ores (materials) |
| 20:00 | **Plan** | choose **the day's one build** at a core spot; report to Mission Control | the upgrade |
| 21:00 | Free time, sleep by 22:30 | movies, games, reading | morale; energy back by morning |
| weekly | Vitals check, Med Bay | bone density, heart rate, blood pressure, wearable sensor | early health warning |

---

## 2. The five core sections

Each section has **one core spot** where all its upgrades are chosen (the panel shows all its tracks); the new
models appear where the things really are (solar field, dome, airlock …).

| Section | Core spot (where you upgrade) | Tracks |
|---|---|---|
| ⚡ **Energy** | Power Room power panel | Day power · Night power · Storm power · Use less |
| 🌱 **Biology** | Greenhouse console | **Food** (greenhouse + water + recycling + food systems + supplies & storage) · Garden dome · Life support (air) |
| ✚ **Health** | Med Bay station | Medical care · **Protection** (radiation shielding, with suits and airlocks) |
| ✦ **Science** | Science workbench / lab glovebox | Lab and materials (makes spare parts from ore) · Scout drone · Rover · Ore survey |
| 📡 **Communication** | Command Room comms console | Comms (suit radio, range, warnings, Earth link) |

HUD stats: Power ⚡, Oxygen O₂, Water, Food, Parts ⚙, Science ✦, Ores ◆, **Radiation ☢ (new)**, crew health / energy
/ suit, **Colony balance (new)**.

---

## 3. Energy (core spot: Power Room)

Research: solar is ~zero at night and drops hard in dust storms (Opportunity 645 → 22 Wh/sol in 2018); **geothermal
is not viable on Mars** (~20–30 mW/m²; InSight never measured it) and appears only as a science fact; wind is
strongest at night and in storms; fission is the go-to night source but not renewable.

| Track | V1 → V5 | Visual |
|---|---|---|
| **Day power** | panels → crew cleans them (task) → **dust shield** (self-cleaning) → **sun trackers** (+25 % clear sols) → multi-junction cells (+50 %) | solar field: dusty rows → clean rows → shield film → tracker mounts → dark high-efficiency panels |
| **Night power** (fork at V3) | batteries → second battery bank → **fork: regenerative fuel cells** (renewable) **or a 10 kWe fission reactor** (allowed, owner; "not renewable" badge, parked away from the base) → bigger of the chosen one | power room racks → tank farm or buried reactor with a berm |
| **Storm power** | test turbine (~0.5 kW) → wind farm (~10 kW per big turbine, more at night and in storms) | turbines on the ridge |
| **Use less** | LEDs −10 % → insulation −10 % → heat recovery −15 % → "run the oxygen plant by day" | technical (icons) |
Dust storms use the real rule solar × e^(−0.3·tau) (§10).

---

## 4. Biology (core spot: Greenhouse console)

### 4.1 Food (greenhouse + water + recycling + food systems + supplies & storage)
NASA Biomass Production Chamber: potato 18.4, wheat 11.3, lettuce 7.1 g/m²/day; ~40–50 m² feeds one person; a full
farm needs ~12–15 kW of light per person, so **food is power-gated**.

| Level | Greenhouse | Water | Recycling | Food and storage |
|---|---|---|---|---|
| V1 | salad pillow: fresh greens, morale | store and ration (1.5 L hygiene per crewmate) | waste and scraps stored | MREs and freeze-dried from shipments |
| V2 | salad and fruit rack (~5 % of calories) | **urine processor + air condensers** (water from breath and sweat) | **compost bin → fertiliser** | cold store: packed food lasts longer |
| V3 | staple farm: potato, dwarf wheat, soy (25–50 %) | **brine processor: 98 %** (like the ISS) + laundry water reuse | compost feeds the farm | bigger stores, fresh food first |
| V4 | full vertical farm, tuned LEDs, fast dwarf crops (~100 %) | water from **clay / gypsum** ore, then an **ice drill** | treated waste → fertiliser | big tanks (also radiation shielding, §5.2) |
| V5 | closed loop: aeroponics, insects eat scraps, less power | | MELiSSA-style closed loop | lab-grown meat ("being researched") |
Visual: greenhouse racks (4 stages exist + a 5th), recycler room, water tanks, ice drill outside.

### 4.2 Garden dome (4 visual stages exist)
Planters → ground cover → shrubs → dwarf fruit trees, then **treated Mars-soil beds** (perchlorate washed out). Food,
O₂ and morale.

### 4.3 Life support, air (4 visual stages exist + a 5th)
V1 tanks + CO₂ scrubber + electrolysis → V2 second scrubber, O₂ buffer → V3 **Sabatier** (~50 % O₂ back from CO₂,
methane to a fuel tank) → V4 **O₂ from Mars air** (scaled-up MOXIE) → V5 75–90 % recovery + plant O₂: nearly closed.

---

## 5. Health (core spot: Med Bay)

### 5.1 Medical care (4 visual stages exist)
Earth is 3–22 min away, so the med bay works alone: V1 first aid + dosimeter badges → V2 ultrasound, vitals monitors →
V3 small lab, dental, minor surgery → V4 surgical bay, imaging, long-life pharmacy. Healing speed, respawn health,
the weekly vitals check (§1.7), and late **radiation care** ("researched, not proven").

### 5.2 Protection: radiation shielding, with suits and airlocks (new stat; visual: the whole base)
Curiosity measured ~0.67 mSv/day on the surface; NASA's career limit is 600 mSv; solar storms are rare but big;
hydrogen-rich shields work best; **a thin soil layer (~30 cm) can be slightly worse than none**. Each level also
upgrades the **suits and airlocks**, so they are part of this track, not their own:

| Level | Base | Suits and airlocks | Daily dose indoors | Solar storm |
|---|---|---|---|---|
| V0 | bare hab | 4 h suit O₂, basic airlock | ~0.67 mSv | full dose |
| V1 | **storm shelter** (room lined with water tanks) | 6 h suit O₂ | same | ÷4 in the shelter |
| V2 | regolith sandbags on roofs (~0.5 m) | dust-proof seals; faster airlock cycle | ~0–10 % lower | ~90 % blocked |
| V3 | **3D-printed regolith shell** (~1–1.5 m) | 8 h suit O₂; storm vest | ~55–60 % lower | ~all blocked |
| V4 | water/ice walls + buried | **suitports** (no air lost, no dust inside) | ~80–90 % lower | ~all blocked |
Dose meter per crewmate on the crew box; outside raises it faster; Communication gives warning before solar storms.

**At the limit (owner, 2026-11-15): the crewmate gets sick and goes into isolation.** At NASA's 600 mSv career limit
the crewmate's health drops, they are moved to an **isolation bed in the Med Bay** and cannot do outdoor or work
blocks (a player controlling them swaps to another crewmate). Medical care levels shorten the time in isolation and
let them come back for indoor work; their dose never resets, so going back outside soon is risky. If every crewmate
is in isolation, the colony cannot run (COLONY OVER, §1.5). Warnings at 400 and 500 mSv.

---

## 6. Science (core spot: science workbench / lab glovebox)

### 6.1 Lab and materials (visual: workbench → full lab; includes the old "workshop")
V1 workbench (identify ores) → V2 laser spectrometer (ChemCam-style assays) → V3 X-ray mineral analyser (CheMin-
style) → V4 **materials lab: turns ores into spare parts and materials** (iron → parts, silica → glass, regolith →
bricks for the radiation shell) → V5 research station (faster science; unlocks late levels in other sections).
**Why it matters:** upgrades cost spare parts, and shipments are rare; the materials lab is how the colony makes its
own, so Science feeds every other section.

### 6.2 Scout drone (owner's design; Blender V1–V4 exist; flies like the owner's FPV example)
Flight feel and screen from `docs/revisions/reference/fpv_drone/`: W A S D move the way the drone faces, the mouse
turns, Space up, Ctrl down, smooth easing, the camera tilts with the stick; the screen shows MANUAL/AUTO + FPV/CHASE, a
compass tape, battery % and time left (low 20 %, critical 10 %), ground speed, home distance, flight time, a reticle,
and a pip row for the flight's survey sites; **"R fly home"**. Tab switches the camera (C opens the crew screen).
**The map is ~560 × 530 m** (base near the middle), so ranges are game-scale:

| Level | Control | Speed | Battery | Reaches (out and back) | Flights per sol | Sensor | New ability |
|---|---|---|---|---|---|---|---|
| V1 | manual only | 3 m/s | 50 s | ~60 m (really close) | 1 | colour + navigation camera | fly it yourself |
| V2 | semi-autonomous | 4.5 m/s | 80 s | ~145 m | 2 | multispectral camera (mini CRISM) | pre-scouts an area and **reports its minerals**; flies itself to **explored** spots |
| V3 | smart search | 5.5 m/s | 95 s | ~210 m | 3 | neutron/gamma spectrometer (water ice) | **"find iron"**: goes to the **known** spots of that ore and checks it is still there |
| V4 | full scan | 6 m/s | 105 s | whole map (~270 m) | 4 | ground radar (RIMFAX-style) | **scans anywhere** for the ore you ask for |
Always keeps enough battery to come home (turns back at the battery it needs); charges at the pad after every flight.
Ingenuity's real flights were 90–169 s at up to 10 m/s over hundreds of metres.

### 6.3 Rover (drivable at every level; add-on parts already follow levels)
**Electric** (Mars air has almost no oxygen; NASA rover studies use batteries, fuel cells or nuclear). Suits last
~6–8 h, so the rover is how you go far. It already drives (4 seats, E, W A S D, Space brakes, Tab view, wheel physics
under Mars gravity, a battery); every level changes its driving numbers:

| Level | Build | Top speed | Battery | Reach |
|---|---|---|---|---|
| V1 | open rover | 3 m/s | 20 kWh | near the base; suit O₂ is the limit |
| V2 | bigger battery packs | 4.8 m/s | 32 kWh | middle ring (§9) |
| V3 | **pressurized cabin + suitport** (also a storm shelter, like NASA's SEV) | 6.2 m/s | 42 kWh | suit O₂ no longer limits trips |
| V4 | fuel-cell range extender (O₂ from the colony's plant) | 7.0 m/s | 48 kWh + fuel cell | far ring |
| V5 | nuclear power cart + sample arm with laser spectrometer | 7.5 m/s | + RTG trickle | whole map, assays on site |
Same-style screen as the drone (speed, battery % and time left, home distance, compass).

### 6.4 Ore survey (technical; the ore data, §9)
Unlocks which ores the drone and rover can see and identify, the map overlay in the J goals view, and the science
explanations (each ore names the real mission that found it).

---

## 7. Communication (core spot: Command Room comms console)

### 7.1 Suit radio (owner, 2026-11-15)
After the tutorial's comms fix (T01) the crew can talk face to face inside the base (as now). The **suit radio** is
its own upgrade path:

| Level | Inside the base | Outside / far from the comms area |
|---|---|---|
| Tutorial fix only | talk to people near you | **suit radio does not send**: "No signal: the suit radio needs a comms upgrade" |
| V1 | suit radio works near the Command Room | **30 s delay and garbled** (crackle, dropped words); it gets smaller every level (owner) |
| V2 | works across the base | ~10 s delay, some crackle |
| V3 | clear | ~2 s delay, clear words, relay mast on the roof |
| V4 | clear | instant and clear across the whole map |
Honest note for the science panel: suit-to-suit radio on Mars is near-instant in real life; the game's delay stands
for a weak signal through a busy base relay. The real **Earth ↔ Mars** delay is 4–24 min, which is why Mission Control
messages arrive late.

### 7.2 The rest of the comms track (visual: 4 stages exist: screens → map wall → relay rack → screen wall and roof dish)
Each level also: longer drone/rover radio range, **earlier warning of dust storms and solar storms** (more time to
get to the shelter), and a better Earth link (bigger, more reliable shipments every ~26 months).

---

## 8. Changed or dropped from draft 1

- **Build points** → **one build a day** (§1.3).
- **Water, recycling, food systems, supplies and storage** → Biology's food track (§4.1).
- **Suits and airlocks** → come with Health's protection track (§5.2).
- **Workshop and fabrication** → Science's materials lab (§6.1). Its point: making spare parts from Mars ore, because
  every upgrade needs parts and shipments are rare.
- **Habitat and crew quarters** → dropped for now. It mainly let the colony house more crew; sleep stays a block in
  the crew's day. It can come back if the colony ever grows beyond four.
- **Command** → is now the Communication section.

---

## 9. Ores across the map (owner, 2026-11-15)

Real ore types from NASA's CRISM mineral list (`research/mars_ores.md`): rust rock (hematite), magnet rock
(magnetite), space metal (iron-nickel meteorites), green gem rock (olivine), Mars dirt (regolith), water clay, water
crystal salt (gypsum), yellow salts (sulfates), pure sulfur, fizz rock (carbonates), glass stone (silica), frozen
water (ice), danger salt (perchlorate). No gold or rare earths (never found on Mars).

**Spread out, richer further out, harder to reach:**

| Ring (from the base) | Distance | What is there | How to reach it |
|---|---|---|---|
| Near | 0–80 m | a little regolith, magnetite in the sand, perchlorate warnings | on foot; drone V1 |
| Middle | 80–170 m | hematite, clay, gypsum, olivine | drone V2 (pre-scout), rover V2, 6 h suit |
| Far | 170–270 m (map edge) | silica, sulfates, ice, carbonates, the rare meteorite metal and pure sulfur | drone V3–V4 scan, rover V3+ cabin, more science to identify |
- More deposits and bigger ones the further out you go, but they need upgrades to reach and science to identify.
- Totals are set so the whole map can pay for about **60 % of all upgrade levels**.
- Deposits are placed by geology on our map (clays in old low ground, ice in shaded north slopes, meteorites on
  open plains), each with "found by …" text from the research.

---

## 10. Mars weather (natural events)

**How it looks today:** good. The game already plays real dust storms (Prompt 09): episodes recorded by
Perseverance's MEDA weather station at Jezero and NASA's daily dust maps (sources W01–W12), played faster, with the
seasons (Ls from the sol count), a warning before each storm that is long enough to walk home, dusty solar panels and
a storm-ready check. Research (`research/mars_weather.md`) confirms it and gives what to add:

| Event | Real science | Game rule (proposal) | Linked upgrade |
|---|---|---|---|
| **Local dust storm** | very common, a few days | 10–20 a Mars year, 1–3 sols, tau 1–2 | Day power (dust shield) |
| **Regional dust storm** | 3 a year (A, B, C) in the dusty season; air up to +35 °C | 5–20 sols, tau 2–5, 3–7 sols' warning | Storm power, Comms (earlier warning) |
| **Global dust storm** | ~1 in 3 Mars years; 2018 hit tau 10.8 and ended Opportunity | grows over 15–30 sols, tau 8–11; warned by the daily pressure wave first | Night + storm power; the hardest test of a colony |
| **Solar power in dust** | Opportunity ~700 → 22 Wh/sol | solar = clear × e^(−0.3·tau) (tau 10.8 → ~4 %) | Day power |
| **Dust devils** | ≥ 4 a sol at Jezero; Spirit's panels got cleaned in 2005, InSight's never did | 4–15 a sol near noon; ~1 % chance a sol of a free panel cleaning | Day power |
| **Wind** | gusts to ~30 m/s, but the air is ~1 % of Earth's: a 30 m/s gust pushes like a 4 m/s breeze | no knockdowns (bust the "The Martian" myth in the science panel); blowing dust lowers visibility and slows the rover | Rover |
| **Temperature** | ground −103 to +17 °C at Gale; dust shrinks the day–night swing | heaters use more power on cold nights | Use less (insulation) |
| **Pressure / frost / clouds** | ~25 % yearly pressure change; winter frost; ice clouds | visual only: frost on the ground some winter mornings, thin clouds | — |
| **Solar storm (radiation)** | 20 May 2024: biggest seen at Mars, ~30 chest X-rays at once | 1–3 big ones a Mars year, 15–60 min warning, 1–3 sols: **get to the storm shelter** | Health protection, Comms warning |
| **Marsquakes** | InSight heard 1,319; biggest M4.7; harmless | science data only (a seismometer reading), never damage | Science |

---

## 11. How we'd build it (after we agree)

1. **Data:** rewrite `data/area_levels.json` as five sections with their tracks, the §1.2 curve, materials, upkeep,
   forks; add `data/ores.json` (types and deposits by ring); new sources (S21+ in `data/sources.json`).
2. **Core spots:** each section's panel at its core spot lists all its tracks; one build a day; the permanent-choice
   card; the colony balance meter.
3. **Stats:** radiation dose (per crewmate, solar-storm events, shelter), COLONY OVER with reasons.
4. **Science vehicles:** drone flight and screen rebuilt on the FPV example (speed and battery from the level),
   flights per sol, mineral reports, "find this ore", full scan; rover numbers per level, same-style screen.
5. **Communication:** suit radio rules (no signal → delay and garble → clear), warning times, ranges.
6. **The crew's day:** schedule clock, blocks, crewmates following it, the evening Plan block (the day's build),
   weekly vitals check, recycling loops.
7. **Models:** one Blender file per visible stage (§1.4), at least 3 per visual track.
8. **Help:** "Press H for help" + gold sparkle path.
Each step can be split across helper agents by file.

---

## 12. Owner decisions (2026-11-15)

| # | Question | Decision |
|---|---|---|
| 1 | Nuclear reactor for night power? | **Yes**, as one side of the night-power fork, with a "not renewable" badge |
| 2 | A crewmate at the radiation limit? | **Gets sick and goes into isolation** in the Med Bay (§5.2) |
| 3 | COLONY OVER timing? | **5-minute countdown** after a life store hits zero (§1.5) |
| 4 | H key? | **H shows the gold sparkle lines** to what matters now; the supplies-bar fold moves to U (§1.6) |
| 5 | The crew's day? | **Strict**, like NASA's timeline; one sol = 20 real minutes by default (§1.7) |
| 6 | Suit radio delay? | **30 s at V1**, smaller every level: 30 → 10 → 2 → instant (§7.1) |
| 7 | One build a day? | **For the whole colony**, voted in the Plan block, so good comms matter (§1.3) |
| — | Earlier | one build a day, no build points; five core sections with core spots; suits/airlocks in Health protection; water, recycling, supplies in Biology food; workshop in Science; crew quarters dropped |

Nothing is open. Next step: build it in the order of §11, split across helper agents by file.

---

## Appendix A: the owner's full astronaut day (2026-11-15, as written)

The game uses the short version in §1.7; this is the full design it comes from.

**Daily schedule**
- **Wake up and personal hygiene, ~06:30.** Use minimal water, 1.5 L per day: wipes instead of showers, wipes to wash
  hands, millilitres for everything else.
- **Check vitals at the Med Bay (once a week):** bone density, heart rate, blood pressure; put on wearable health
  sensors.
- **Breakfast, ~07:00 (mess hall):** vegetables from the garden dome and greenhouse, lab-grown meat; food heated in a
  "microwave" (electric heating, no open flames); extra food goes into compost.
- **Check energy systems, 07:30** (split up, divide and conquer): energy diversions, clean solar panels, check
  batteries.
- **Morning research block, 08:00:**
  - Biologist: greenhouse and garden dome, how the plants are doing, experiments; also study how the crew get on and
    look for microbial ecosystems.
  - Geologist: go outside and collect rocks and dust to examine for life or chemicals; dig into rocks too.
  - Engineering: check everything, see if anything needs fixing, check efficiency levels.
  - Medical: keep track of everyone's vitals and look for any that are dropping.
- **Lunch, 12:00 (mess hall):** same as breakfast; part of research into how the body uses food and how efficient
  food production is.
- **Mandatory exercise, 12:30:** track heart, muscle and bone changes; resistance machines, treadmills, bikes.
- **Habitat operations, 14:30:** go round and check systems (oxygen production; water filtration and storing water in
  the right systems; energy diversion; rover maintenance); upload data and log research; collect and store any
  supply drop in the right place; tidy areas; wash clothes.
- **Exploration and field missions, 18:00:** take rovers out for data (not everyone, at least 2 people); geology and
  setting up science instruments.
- **Dinner, 19:30:** like lunch but heavier on potatoes and protein.
- **Evening research, 20:00:** what research needs doing, what needs fixing, design colony expansions and note what
  to add, report the day's findings.
- **Recreation, 21:00:** movies, games, reading.
- **Sleep by 22:30.**

**How recycling is done**
- Fertiliser: toilet waste is stored as fertiliser; food scraps go into a compost bin.
- Water: the bathroom sends water into a separate container; condensers in the air catch water drops (from breathing
  and sweat) in trays for later; the washing machine collects and reuses water and sweat.
- Air: air filtration systems.

**Food systems**
- Astronauts get food from shipments and from growing it; shipments bring MREs and freeze-dried food.

---

## Sources

Full notes, numbers and caveats for each are in `docs/revisions/research/`. When we build, these become new entries
in `data/sources.json` (S21 onward) so the game's science panels can cite them.

**Mars ores and minerals** (`research/mars_ores.md`)
1. Ehlmann & Edwards 2014, Mineralogy of the Martian Surface, Annu. Rev. Earth Planet. Sci. 42:291 — https://authors.library.caltech.edu/records/635vw-7ga04
2. MICA, Minerals Identified through CRISM Analysis (Viviano-Beck et al. 2014, JGR Planets) — https://crismtypespectra.rsl.wustl.edu
3. NASA PDS Geosciences Node — https://pds-geosciences.wustl.edu
4. Mars Orbital Data Explorer — https://ode.rsl.wustl.edu/mars
5. Christensen et al. 2000, hematite at Meridiani (MGS TES) — https://themis.asu.edu/projects/tes
6. Rampe et al. 2020, CheMin minerals at Gale crater — https://authors.library.caltech.edu/100907
7. Hecht et al. 2009, perchlorate at the Phoenix site — https://experts.arizona.edu/en/publications/detection-of-perchlorate-and-the-soluble-chemistry-of-martian-soi/
8. Ehlmann et al. 2008, carbonates at Nili Fossae — https://resolver.caltech.edu/CaltechAUTHORS:20121016-112524059
9. Squyres et al. 2008, silica at Home Plate — https://news.asu.edu/content/mars-rover-finds-yellowstone-hot-spring-deposits
10. Morris et al. 2016, tridymite at Gale — https://www.jpl.nasa.gov/news/nasa-scientists-discover-unexpected-mineral-on-mars/
11. Tanaka et al. 2014, USGS Geologic Map of Mars (SIM 3292) — https://pubs.usgs.gov/sim/3292
12. SWIM buried-ice maps — https://photojournal.jpl.nasa.gov/catalog/PIA26045
13. Langevin 2005, gypsum near the north pole (ESA Mars Express) — https://sci.esa.int/web/mars-express/-/36816-sulfates-in-the-north-polar-region-of-mars
14. Curiosity's "Lebanon" iron meteorite — https://science.nasa.gov/resource/curiosity-finds-iron-meteorite-on-mars/
15. Curiosity finds pure sulfur, 2024 — https://www.space.com/nasa-mars-curiosity-sulfur-rocks
16. Mars air composition (Curiosity SAM) — https://eos.org/research-spotlights/curiosity-rover-reveals-oxygen-mystery-in-martian-atmosphere

**Power** (`research/mars_power.md`)
17. NASA Mars fact sheet — https://nssdc.gsfc.nasa.gov/planetary/factsheet/marsfact.html
18. JPL, InSight waits out a dust storm (2022) — https://www.jpl.nasa.gov/news/nasas-insight-waits-out-dust-storm/
19. The Planetary Society, Opportunity and the 2018 dust storm — https://www.planetary.org/articles/06-mer-update-opportunity-dust-storm-sleep
20. NASA, dust shield works on the Moon (2025) — https://www.nasa.gov/image-article/nasas-dust-shield-successfully-repels-lunar-regolith-on-moon/
21. Hartwick et al. 2023, wind as a power source on Mars, Nature Astronomy 7 — https://www.nature.com/articles/s41550-022-01851-4
22. KRUSTY / Kilopower test results (NTRS) — https://ntrs.nasa.gov/citations/20180005435
23. Rucker 2016, solar vs fission surface power for Mars — https://ntrs.nasa.gov/citations/20160002628
24. Rucker 2015, integrated surface power strategy for Mars — https://ntrs.nasa.gov/citations/20150000526
25. NASA MMRTG fact sheet — https://science.nasa.gov/wp-content/uploads/2024/02/mmrtg-factsheet-updated-5-18-20-1.pdf
26. Spohn et al. 2018, InSight HP3 heat probe — https://link.springer.com/article/10.1007/s11214-018-0531-4
27. NASA TM-20210024659, fuel cells vs Li-ion — https://ntrs.nasa.gov/api/citations/20210024659/downloads/TM-20210024659.pdf
28. Abel et al. 2022 (UC Berkeley), solar vs nuclear by site — https://news.berkeley.edu/2022/04/27/solar-beats-nuclear-at-many-potential-settlement-sites-on-mars/
29. 40 kW Fission Surface Power design — https://ntrs.nasa.gov/api/citations/20220004670/downloads/40%20kW%20Deployable%20FSP%20Paper_FINAL.pdf

**Rover and drone** (`research/mars_rover_drone.md`)
30. NASA Space Exploration Vehicle fact sheet — https://www.nasa.gov/wp-content/uploads/2015/08/464826main_sev_factsheet_508.pdf
31. NASA TM-2022-0006678, Mars pressurized rover power trades — https://ntrs.nasa.gov/citations/20220006678
32. Apollo Lunar Roving Vehicle (NSSDC) — https://nssdc.gsfc.nasa.gov/planetary/lunar/apollo_lrv.html
33. Zubrin & Baker 1993, Mars Direct (methane/oxygen rover) — https://marspapers.org/paper/Zubrin_1993_2.pdf
34. Extravehicular Mobility Unit (spacesuit time; secondary source) — https://en.wikipedia.org/wiki/Extravehicular_Mobility_Unit
35. NASA xEMU EVA testing — https://ntrs.nasa.gov/api/citations/20210000827/downloads/Exporation%20EVA%20Testing%20and%20Analogs%2020210000827.pdf
36. Ingenuity Mars Helicopter fact sheet — https://mars.nasa.gov/files/mars2020/MarsHelicopterIngenuity_FactSheet.pdf
37. Ingenuity mission page (72 flights, 17 km) — https://science.nasa.gov/mission/mars-2020-perseverance/ingenuity-mars-helicopter/
38. Ingenuity's record flight 25 — https://www.space.com/mars-helicopter-ingenuity-record-breaking-25th-flight
39. Mars Science Helicopter concept (NASA Ames) — https://ntrs.nasa.gov/citations/20200002139
40. Dragonfly (Titan) — https://science.nasa.gov/mission/dragonfly/
41. Mars Odyssey finds water ice — https://www.jpl.nasa.gov/news/odyssey-finds-water-ice-in-abundance-under-mars-surface/
42. First Sony lithium-ion cells (battery history) — https://www.osti.gov/biblio/7047720

**Radiation, food, life support, medicine** (`research/mars_radiation_food_life.md`)
43. Curiosity RAD surface dose (Hassler) — https://www.space.com/23875-mars-radiation-life-manned-mission.html
44. Hassler et al. 2014, Science — https://doi.org/10.1126/science.1244797
45. NASA OCHMO radiation protection brief (600 mSv limit) — https://www.nasa.gov/wp-content/uploads/2023/03/radiation-protection-technical-brief-ochmo.pdf
46. The May 2024 solar storm at Mars — https://www.space.com/mars-aurora-radiation-solar-storm-curiosity-rover
47. Zhang et al. 2022, how much soil shields Mars crews — https://www.space.com/mars-radiation-protection-astronauts-underground
48. Löwe et al. 2025, solar-storm warnings on Mars — https://arxiv.org/abs/2502.02469
49. Radiation in Mars lava tubes — https://arxiv.org/pdf/2004.13156
50. NASA Mars Ice Home — https://phys.org/news/2016-12-nasa-ice-house-mars.amp
51. NASA 3D-Printed Habitat Challenge — https://www.space.com/nasa-3d-printed-habitat-competition-winners.html
52. Wheeler, NASA Biomass Production Chamber — https://ntrs.nasa.gov/citations/20040089951
53. Wheeler 2017, Agriculture for Space — https://sciences.ucf.edu/class/wp-content/uploads/sites/23/2017/02/Wheeler_AgricultureForSpace_PeoplePlaces_OpenAgriculture_2017.pdf
54. Kusuma, Pattison & Bugbee 2020, LED efficiency — https://pubmed.ncbi.nlm.nih.gov/32257242/
55. ISS reaches 98 % water recovery — https://www.space.com/astronaut-pee-iss-water-recycling-98-percent-milestone
56. ISS oxygen loop (ICES 2024) — https://ntrs.nasa.gov/api/citations/20240002161/downloads/ICES24%20Paper%20168.pdf
57. MOXIE makes the first oxygen on Mars (JPL) — https://www.jpl.nasa.gov/news/nasas-perseverance-mars-rover-extracts-first-oxygen-from-red-planet/
58. Oze et al. 2021, perchlorate and plants — https://mdpi.com/2571-8789/5/3/37
59. NASA food shelf life — https://ntrs.nasa.gov/api/citations/20140010665/downloads/20140010665.pdf

**Mars weather** (`research/mars_weather.md`; the game's existing weather data is W01–W12 in `data/sources_weather.json`)
61. NASA, fact and fiction of Martian dust storms — https://www.nasa.gov/content/the-fact-and-fiction-of-martian-dust-storms
62. JPL, Mars orbiters reveal a seasonal dust-storm pattern — https://www.jpl.nasa.gov/news/nasa-mars-orbiters-reveal-seasonal-dust-storm-pattern/
63. The Planetary Society, Opportunity sleeps (tau 10.8) — https://www.planetary.org/articles/08-mer-update-opportunity-sleeps
64. JPL, Opportunity hunkers down during a dust storm — https://www.jpl.nasa.gov/news/opportunity-hunkers-down-during-dust-storm/
65. JPL, the 2001 dust storm swallows half of Mars — https://www.jpl.nasa.gov/news/dust-storm-swallows-half-of-mars/
66. Guzewich et al. 2019, Curiosity in the 2018 global storm (GRL) — https://ui.adsabs.harvard.edu/abs/2019GeoRL..46...71G
67. Viúdez-Moreiras, the 2018 storm at Gale crater — https://www.inta.es/export/sites/default/.galleries/cpess6-Descarga/Viudez-Moreiras-D_The-Impact-of-the-MY34-2018-Global-Dust-Storm-on-the-near-surface-atmosphere-in-Gale-Crater-Mars.pdf
68. MRO MARCI weekly Mars weather report — https://www.jpl.nasa.gov/images/pia11418-mro-marci-weather-report-for-the-week-of-3-november-2008-9-november-2008/
69. NASA, Perseverance studies the winds of Jezero crater — https://www.nasa.gov/missions/mars-2020-perseverance/perseverance-rover/nasas-perseverance-studies-the-wild-winds-of-jezero-crater/
70. Spiga et al. 2020, InSight's dust devils and vortices — https://arxiv.org/pdf/2005.01134
71. Spirit's 2005 panel-cleaning event — https://spaceflightnow.com/mars/mera/050314dustdevil.html
72. JPL, Curiosity's seasonal cycles (pressure, humidity) — https://www.jpl.nasa.gov/images/pia20600-seasonal-cycles-in-curiositys-first-two-martian-years/
73. The Planetary Society, the Mars calendar — https://www.planetary.org/articles/mars-calendar
74. NASA, Mars lights up during the May 2024 solar storm — https://www.nasa.gov/solar-system/planets/mars/nasa-watches-mars-light-up-during-epic-solar-storm/
75. InSight's biggest marsquake (M4.7) — https://www.space.com/mars-insight-most-powerful-marsquake
76. HiRISE, moving dunes at Nili Patera — https://hirise.lpl.arizona.edu/ESP_028575_1890

**Owner's reference project**
60. `fpv-drone.zip` (owner, 2026-11-15), kept in `docs/revisions/reference/fpv_drone/`: flight controller and
    on-screen display. Its model "FPV Racer" (Robots and Drones Kit, 3DAssets.dev) is CC0 1.0 —
    https://3dassets.dev/assets/robots-and-drones-kit-fpv-racer-f1c0cf37 ; font IBM Plex Mono, SIL Open Font Licence.
