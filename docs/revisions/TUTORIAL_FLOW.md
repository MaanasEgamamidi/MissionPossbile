# The tutorial, as the players see it (2026-11-14)

This replaces the Prompt Pack's old 10-stage tutorial (walk, airlock, hub, solar, energy, greenhouse, health, comms,
greenhouse fault, explore) with the flow from your whiteboard. The words the game shows are in `data/tutorial.json`.

## The story

It is the 2060s and Earth is in trouble: people need a new home. The players are the second team on Mars. The first
team could not finish their mission, and their tapes tell what happened. **Mission Control** is the guide: short
messages that start with "Mission Control:". The game never says the first team died (the game is for ages 9 to 12);
tell us if you want that said more strongly.

## Step 1: Arrival

- A new game starts with every crew member in a suit, right outside the exit-tunnel door. Every door in the base is
  held open.
- Mission Control welcomes the crew and says the crew radio is broken. **Crew voice chat is off** (talking and
  hearing). The voice line on screen says: "Crew radio is down: only Mission Control can reach you. Fix the radio
  signal in the Command Room to talk to your crew."
- The step ends as soon as anyone walks into the base.

## Step 2: The first team's tapes

- Mission Control: find the 6 tapes, one in each main room (Command Room, Power Room, Greenhouse, Garden dome, Med Bay,
  Hangar), then play them on the cassette player in the Command Room.
- The tracker on the right and the goal card (J) show **Tapes found n/6** and **Tapes played n/6**. A tape counts as
  played when someone chooses it on the Command Room cassette player. Tapes are shared by the whole crew.

## Step 3: Fix the base

- When all 6 tapes have been played, Mission Control says: **"Fix the base: get it to operational condition."**
- The tracker lists the 10 broken spots by room, with the specialist each one needs:
  - Command Room: fix the radio signal (anyone), fix the wires (⚡ Electrical and comms)
  - Power Room: fix the power dials (anyone), repair the power circuit (⚡ Electrical and comms)
  - Greenhouse: fix the broken pipe (anyone)
  - Garden dome: repair the broken glass (anyone)
  - Med Bay: fix the test-tube rack (✚ Medical and life support), fix the unplugged equipment (anyone)
  - Hangar and airlock: clean the dusty hangar (anyone), repair the air leak (⛏ Field engineering and geology)
- T05 and T07 have no broken part and are not needed.
- The goal card shows each room with its count ("Fix the Command Room 1/2"). A room is **restored** when all its broken
  spots are fixed, and Mission Control says so. Each fix is counted out loud ("The wires are fixed. 3 of 10 fixed.").
- Fixing the radio signal (T01) brings crew voice back, and Mission Control says so.
- A spot fixed early (while the tapes are still being found) counts too. The tutorial still waits for all 6 tapes.

## Done: Base operational

- When all 10 spots are fixed, the tutorial is done: the doors stop being held open and work normally again, and
  Mission Control says "The base is operational!".
- The game records the moment (`campaign.base_operational`, with the time). The beauty shot of the fixed base plays
  from that (the cinematics part, built by another worker).
- After that, the colony goal from before stays: get all five sectors and the radio working, then keep the battery,
  water, oxygen and food above zero for one whole sol. (Kept, because it fits well after the base works.)

## Only tapes and broken parts respond to E

While the tutorial runs, these still work: the doors, the suit rack, the tapes, the Command Room cassette player, every
broken spot that is still broken, and the crew screen (C) at the Med Bay hub. Every other machine shows no "[E]" prompt.
If a player still presses E there, nothing opens and a message says: "Not yet: Mission Control needs the base fixed
first. For now only the tapes and the broken spots work." A spot that is already fixed says it is fixed and that the
other machines work again when the whole base is fixed. After the tutorial everything works as before.

## The wrong specialist sees gibberish

If someone opens a specialist's broken spot without being that specialist, the mini-game window opens but shows
scrambled symbols instead of the controls, and one clear line, for example: "Only the ✚ Medical and life support
specialist can read this. Press C to swap to them at the Med Bay hub." With four players (no swapping) it says to ask
that player, and if another player already plays that specialist it says to ask them. Nothing can be done in the
scrambled window. Jobs for anyone open for everybody.

## Saving, joining and the journal

- Everything (tapes found and played, spots fixed, rooms restored, Mission Control's lines, Base operational) is saved
  and shared with every player. A player who joins late sees the same step and counts.
- The colony journal (L) shows the step, the checklist, everything Mission Control said, and a "Remind me" button that
  repeats Mission Control's words for a finished step.
- Saves from the old tutorial: a colony that had finished it stays finished; an unfinished one starts this new flow.
