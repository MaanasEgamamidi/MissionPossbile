class_name CommsStage
extends RefCounted
## The colony radio's equipment stage (Prompt 11). Stage 0: no exterior link. Stages 1-4: the radio passes speech
## after 30 s, 15 s, 5 s, then near-immediately. The delay is the damaged equipment's buffering and processing; it is
## not network delay and not Earth-Mars light time. Stages are upgrade cards installed at the communications station.
## INTERFACE STUB written before the parallel work; the voice worker owns this file and may extend it.

## Upgrade card ids, one per stage, installed in order.
const CARD_IDS: PackedStringArray = ["comms_radio_1", "comms_radio_2", "comms_radio_3", "comms_radio_4"]
## Intentional radio delay per stage in real seconds; stage 0 has no link (-1).
const DELAY_S: PackedFloat32Array = [-1.0, 30.0, 15.0, 5.0, 0.0]


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
