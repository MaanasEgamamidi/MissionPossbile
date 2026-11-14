class_name PowerModel
extends RefCounted
## Energy model: 12 sun trackers, dust on the panels and the automatic cleaner, the battery, and the loads.
## Pure functions on ColonyState; no nodes.
##
## Each tick:
##   supply = solar + what the battery can give (bounded by its maximum power and by its charge)
##   demand = base load + lights of each switched-on zone + every switched-on piece of equipment
##   while demand > supply, whole load groups are shed, lowest priority first (SHED_ORDER).
##   Solar feeds the powered loads first, the battery covers the rest, surplus solar charges the battery
##   (energy stored = energy in x efficiency), and what still does not fit is curtailed.
## Ledger identities (kWh):
##   battery now = battery at start + battery_in - battery_loss - battery_out
##   solar_offered = solar_used + solar_curtailed          load_served = solar to loads + battery_out

## Load groups in shedding order: the first one is shed first when supply is short.
const SHED_ORDER: Array[String] = ["lights", "greenhouse", "co2_unit", "electrolyser", "recycler", "trackers", "cleaner", "scrubber", "cabin_fans", "base"]
const GREENHOUSE_ZONE := "Greenhouse"
const SUNRISE := 0.25
const SUNSET := 0.75

## Plain names for alerts and panels.
const LABELS := {
	"lights": "Room lights", "greenhouse": "Greenhouse lights", "co2_unit": "CO2-oxygen unit", "electrolyser": "Electrolyser",
	"recycler": "Water recycler", "trackers": "Sun trackers", "cleaner": "Panel cleaner", "scrubber": "CO2 scrubber",
	"cabin_fans": "Cabin fans", "base": "Control and heating",
}
## What happens when a group loses power: cause and effect in plain words.
const SHED_TEXT := {
	"lights": "Room lights stopped: no power. Rooms that are not critical go dark.",
	"greenhouse": "Greenhouse lights stopped: no power. The plants get no light.",
	"co2_unit": "CO2-oxygen unit stopped: no power. It makes no oxygen.",
	"electrolyser": "Electrolyser stopped: no power. It makes no oxygen.",
	"recycler": "Water pump stopped: no power. Wastewater is building up.",
	"trackers": "Sun trackers stopped: no power. The panels stay fixed and make less power.",
	"cleaner": "Panel cleaner stopped: no power. Dust stays on the panels.",
	"scrubber": "CO2 scrubber stopped: no power. Carbon dioxide is building up in the cabin.",
	"cabin_fans": "Cabin fans stopped: no power. Air moves slowly through the CO2 scrubber.",
	"base": "Control and heating stopped: no power at all. Switch things off and wait for the sun.",
}


## Share of a panel's peak output from the sun's position. Between sunrise and sunset the sun follows a half sine;
## a powered tracker turns its panel to face the sun (square root of the half sine), a fixed panel does not.
static func sun_term(phase: float, tracking: bool) -> float:
	if phase <= SUNRISE or phase >= SUNSET:
		return 0.0
	var s := sin(PI * (phase - SUNRISE) / (SUNSET - SUNRISE))
	return sqrt(s) if tracking else s


## Dust in the air blocks sunlight: exp(-factor x tau), normalised so the default dust_tau gives 1.0.
static func atmosphere_term(state: ColonyState, balance: GameBalance) -> float:
	return exp(-balance.dust_tau_factor * (state.dust_tau - balance.dust_tau_default))


## True if the tracker drives can turn the panels: switched on and in working condition (power is checked separately).
static func trackers_can_track(state: ColonyState, balance: GameBalance) -> bool:
	return state.is_on("trackers") and state.condition_of("trackers") >= balance.equipment_min_condition


## Output of one tracker in kW.
static func tracker_kw(state: ColonyState, balance: GameBalance, phase: float, tracking: bool, index: int) -> float:
	var dust := clampf(float(state.panel_dust[index]), 0.0, 1.0)
	return balance.solar_kw_peak / float(ColonyState.TRACKER_COUNT) * sun_term(phase, tracking) * atmosphere_term(state, balance) \
		* (1.0 - dust) * clampf(state.condition_of("trackers"), 0.0, 1.0)


## Output of all trackers in kW.
static func solar_kw(state: ColonyState, balance: GameBalance, phase: float, tracking: bool) -> float:
	var total := 0.0
	for i in ColonyState.TRACKER_COUNT:
		total += tracker_kw(state, balance, phase, tracking, i)
	return total


## Power one piece of equipment asks for while switched on. Equipment below working condition does not run.
## The two oxygen processes ask for what their planned output needs (`process_kw`).
static func equipment_kw(state: ColonyState, balance: GameBalance, id: String, process_kw: Dictionary) -> float:
	if state.condition_of(id) < balance.equipment_min_condition:
		return 0.0
	match id:
		"trackers": return balance.tracker_drive_kw
		"cleaner": return balance.cleaner_kw
		"recycler": return balance.recycler_kw
		"scrubber": return balance.scrubber_kw
		"cabin_fans": return balance.cabin_fans_kw
		_: return float(process_kw.get(id, 0.0))


## Switched-on load groups with their kW, in SHED_ORDER. Critical room lights count as part of the base load.
static func demand_groups(state: ColonyState, balance: GameBalance, process_kw: Dictionary) -> Array[Dictionary]:
	var kw := {"base": balance.base_load_kw}
	for zone: String in state.zones:
		if not state.is_zone_powered(zone):
			continue
		var group := "lights"
		if zone == GREENHOUSE_ZONE:
			group = "greenhouse"
		elif balance.critical_light_zones.has(zone):
			group = "base"
		kw[group] = float(kw.get(group, 0.0)) + balance.load_of_zone(zone)
	for id in ColonyState.EQUIPMENT_IDS:
		if state.is_on(id):
			kw[id] = equipment_kw(state, balance, id, process_kw)
	var out: Array[Dictionary] = []
	for id in SHED_ORDER:
		if kw.has(id):
			out.append({"id": id, "kw": float(kw[id])})
	return out


## Allocates power for one tick of `dt` game hours and moves the energy. Sets every equipment's "powered" and "kw",
## the display flows and the ledger. Returns {"shed": Array[String], "tracking": bool, "solar_kw": float}.
static func allocate(state: ColonyState, balance: GameBalance, phase: float, dt: float, process_kw: Dictionary) -> Dictionary:
	var groups := demand_groups(state, balance, process_kw)
	var demand := 0.0
	for g in groups:
		demand += float(g.kw)
	var wanted_kw := demand
	var battery_max_kw := minf(balance.battery_discharge_kw_max, state.store(&"battery_kwh") / dt)
	var tracking := trackers_can_track(state, balance)
	var solar := solar_kw(state, balance, phase, tracking)
	var shed: Array[String] = []
	for g in groups:
		if demand <= solar + battery_max_kw + 1e-12:
			break
		shed.append(String(g.id))
		demand -= float(g.kw)
		if g.id == "trackers" and tracking:
			tracking = false                                   # unpowered trackers stay fixed: less sun on the panels
			solar = solar_kw(state, balance, phase, false)
	demand = maxf(0.0, demand)

	# ---- move the energy
	var direct := minf(solar, demand)                          # kW straight from the sun to the loads
	var out := -state.add_to_store(&"battery_kwh", -(demand - direct) * dt)
	var surplus := (solar - direct) * dt
	var eff := balance.battery_charge_efficiency
	var e_in := minf(surplus, balance.battery_charge_kw_max * dt)
	if eff > 0.0:
		e_in = minf(e_in, state.room_in(&"battery_kwh") / eff)
	else:
		e_in = 0.0
	e_in = maxf(0.0, e_in)
	var stored := state.add_to_store(&"battery_kwh", e_in * eff)
	var served := direct * dt + out
	state.ledger["solar_offered_kwh"] += solar * dt
	state.ledger["solar_used_kwh"] += direct * dt + e_in
	state.ledger["solar_curtailed_kwh"] += surplus - e_in
	state.ledger["battery_in_kwh"] += e_in
	state.ledger["battery_loss_kwh"] += e_in - stored
	state.ledger["battery_out_kwh"] += out
	state.ledger["load_served_kwh"] += served
	state.ledger["load_unserved_kwh"] += (wanted_kw - demand) * dt          # the shed loads; the battery always covers the rest

	# ---- equipment and display
	for id in ColonyState.EQUIPMENT_IDS:
		var e: Dictionary = state.equipment[id]
		e["kw"] = equipment_kw(state, balance, id, process_kw) if bool(e.on) else 0.0
		e["powered"] = bool(e.on) and not shed.has(id)
	state.solar_kw = solar
	state.load_kw = wanted_kw
	state.served_kw = served / dt
	state.battery_kw = (stored - out) / dt
	state.shed = []
	for id in shed:
		state.shed.append(id)
	state.power_deficit = not shed.is_empty()
	return {"shed": shed, "tracking": tracking, "solar_kw": solar}


## True if a tick that starts at `phase` and lasts `dt` game hours passes sunrise.
static func crosses_sunrise(phase: float, dt: float) -> bool:
	var end := phase + dt / GameConfig.SOL_HOURS
	return floorf(end - SUNRISE) > floorf(phase - SUNRISE)


## Dust settles on every panel; a working cleaner (on, in condition and powered) wipes all of them once per sol at
## sunrise. Returns true if the cleaner ran this tick.
static func settle_dust(state: ColonyState, balance: GameBalance, phase: float, dt: float) -> bool:
	var add := balance.dust_deposit_per_sol * (state.dust_tau / balance.dust_tau_default) * dt / GameConfig.SOL_HOURS
	for i in ColonyState.TRACKER_COUNT:
		state.panel_dust[i] = clampf(float(state.panel_dust[i]) + add, 0.0, 1.0)
	if cleaner_working(state, balance) and crosses_sunrise(phase, dt):
		for i in ColonyState.TRACKER_COUNT:
			state.panel_dust[i] = 0.0
		return true
	return false


static func cleaner_working(state: ColonyState, balance: GameBalance) -> bool:
	return state.is_on("cleaner") and state.condition_of("cleaner") >= balance.equipment_min_condition and state.is_powered("cleaner")


static func average_dust(state: ColonyState) -> float:
	var total := 0.0
	for d: Variant in state.panel_dust:
		total += float(d)
	return total / float(maxi(1, state.panel_dust.size()))


## Energy alerts as [id, level, text]. `phase` is the time of day at the end of the tick.
static func alerts(state: ColonyState, balance: GameBalance, phase: float) -> Array:
	var out: Array = []
	for id: String in state.shed:
		var level := "urgent" if id == "base" or id == "scrubber" or id == "cabin_fans" else "warn"
		out.append(["shed_" + id, level, String(SHED_TEXT[id])])
	var battery := state.store(&"battery_kwh")
	var cap := float(state.capacities.get(&"battery_kwh", 0.0))
	if cap > 0.0 and battery < balance.battery_warn_fraction * cap:
		out.append(["battery_low", "warn", "Battery low: %.0f kWh left. Switch off lights and machines you do not need." % battery])
	var night := phase <= SUNRISE or phase >= SUNSET
	if night and state.battery_kw < -1e-9 and battery > 0.0:
		var to_sunrise := fposmod(SUNRISE - phase, 1.0) * GameConfig.SOL_HOURS
		var lasts := battery / -state.battery_kw
		if lasts < to_sunrise:
			out.append(["battery_short_night", "warn", "Battery will run out about %.0f hours before sunrise at this rate. Switch off what you do not need." % (to_sunrise - lasts)])
	if state.condition_of("cleaner") < balance.equipment_min_condition:
		out.append(["cleaner_failed", "warn", "Panel cleaner is broken. Dust stays on the panels, so they make less power. An electrical specialist can repair it at a sun tracker."])
	elif not state.is_on("cleaner"):
		out.append(["cleaner_off", "info", "Panel cleaner is switched off. Dust stays on the panels."])
	var dust := average_dust(state)
	if dust >= 0.2:
		out.append(["panels_dusty", "info", "Solar panels are dusty: they make about %.0f %% less power. Clean them at the trackers." % (dust * 100.0)])
	if not state.is_on("trackers"):
		out.append(["trackers_off", "info", "Sun trackers are switched off. The panels stay fixed and make less power."])
	elif state.condition_of("trackers") < balance.equipment_min_condition:
		out.append(["trackers_broken", "warn", "Sun trackers are broken. The panels stay fixed and make less power."])
	return out
