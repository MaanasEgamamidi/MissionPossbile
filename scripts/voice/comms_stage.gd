class_name CommsStage
extends RefCounted
## The colony radio's equipment stage (Prompt 11). Stage 0: no exterior link. Stages 1-4: the radio passes speech
## after 30 s, 15 s, 5 s, then near-immediately. The delay is the damaged equipment's buffering and processing; it is
## not network delay and not Earth-Mars light time. Stages are upgrade cards installed at the communications station.
##
## The four cards live in data/upgrades.json in the energy sector (the electrical systems sector, installed by the
## electrical and comms specialist): communications is not a sixth tier sector of ProgressionSystem. They are chained
## by prerequisites, so they install in order: comms_radio_1 needs no sector level, 2 needs Energy level 1, 3 Energy
## level 2, 4 Energy level 3. Messages from Earth are a separate system and are never made faster by these cards.

## Upgrade card ids, one per stage, installed in order.
const CARD_IDS: PackedStringArray = ["comms_radio_1", "comms_radio_2", "comms_radio_3", "comms_radio_4"]
## Intentional radio delay per stage in real seconds; stage 0 has no link (-1). Contract values (the brief).
const DELAY_S: PackedFloat32Array = [-1.0, 30.0, 15.0, 5.0, 0.0]
## Parts each card costs, stage 1..4 (contract: 1, 2, 3, 4).
const CARD_PARTS: PackedInt32Array = [1, 2, 3, 4]
## Station kind where the cards are installed (the existing communications station, cm_comms_console).
const INSTALL_KIND := "comms"
const INSTALL_STATION := "cm_comms_console"
## Specialist who installs them.
const SPECIALTY := &"electrical_comms"
const MAX_STAGE := 4


## Installed stage, 0..4.
static func stage(state: ColonyState) -> int:
	var n := 0
	for id: String in CARD_IDS:
		if state != null and state.has_upgrade(id):
			n += 1
		else:
			break
	return n


## Intentional delay in seconds for a stage; -1 when there is no exterior link.
static func delay_seconds(p_stage: int) -> float:
	return float(DELAY_S[clampi(p_stage, 0, DELAY_S.size() - 1)])


## True when the radio carries speech at all (stage 1 or more).
static func has_link(p_stage: int) -> bool:
	return delay_seconds(p_stage) >= 0.0


## The card that would raise the radio to the next stage, or "" at stage 4.
static func next_card(state: ColonyState) -> String:
	var s := stage(state)
	return CARD_IDS[s] if s < CARD_IDS.size() else ""


## How long the radio holds speech, in words: "after 30 s", "almost at once"; "" for no link.
static func delay_words(p_stage: int) -> String:
	var d := delay_seconds(p_stage)
	if d < 0.0:
		return ""
	if d <= 0.0:
		return "almost at once"
	return "after %d s" % roundi(d)


## One line for the HUD and the panels: "Radio stage 2 of 4: speech is heard after 15 s."
static func stage_text(p_stage: int) -> String:
	if not has_link(p_stage):
		return "Radio stage 0 of 4: no radio link outside. Repair the radio at the comms console."
	return "Radio stage %d of 4: speech is heard %s." % [p_stage, delay_words(p_stage)]


## Why the radio is slow, in plain words (shown in the voice settings and on the HUD help).
static func explanation() -> String:
	return ("The colony radio is damaged. It has to store your words and clean them up before it can send them, "
		+ "so people hear you later. That wait is the radio's own buffering and processing. It is not the computer "
		+ "network and not the distance to Earth. Each repair at the comms console makes the wait shorter: 30 s, 15 s, "
		+ "5 s, then almost none. Messages from Earth still take many minutes, because radio waves need that long to "
		+ "cross the space between the planets; repairing the colony radio cannot change that.")
