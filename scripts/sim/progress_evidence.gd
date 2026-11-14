class_name ProgressEvidence
extends RefCounted
## The one way any part of the game records practical evidence for upgrades (Prompt 08). Host only.
## Evidence is shared colony progress: it is stored once per id, so repeating a task never adds more.
##   state.evidence[evidence_id] = {"by": character id, "sector": "...", "at_hours": game hours, "detail": {...}}


## Records `evidence_id` for `sector` if it is not already recorded. Returns true when it is new.
## Emits events.upgrade_eligibility_changed(evidence_id) so the upgrade cards refresh.
static func record(state: ColonyState, events: GameEvents, evidence_id: StringName, sector: String, actor: StringName, detail := {}) -> bool:
	var key := String(evidence_id)
	if state.evidence.has(key):
		return false
	state.evidence[key] = {"by": String(actor), "sector": sector, "at_hours": state.sim_hours, "detail": detail.duplicate(true)}
	if events != null:
		events.upgrade_eligibility_changed.emit(evidence_id)
	return true


static func has(state: ColonyState, evidence_id: StringName) -> bool:
	return state.evidence.has(String(evidence_id))
