class_name WeatherConfig
extends Resource
## Numbers of the weather part (Prompt 09): the data refresh, the dust-event scheduler, the warning and return margin,
## and the sky presentation. Every field says its category, the same as in data/model_sources_weather.json:
##   balance               game tuning with no source; never a NASA figure
##   game transformation   how archive observations are turned into game events (accelerated gaps, severity scaling);
##                         NOT the storm frequency observed by NASA
##   engineering           software behaviour (timeouts, retries, sizes)
##   physics               standard science
##   contract              a number fixed by the project brief or contract
##   S01 / S02             register sources (Mars Fact Sheet, Mars24 notes)
## Archive values themselves (opacity curves, wind, sols, Ls) come from the data bundle, never from here.

@export_group("Data refresh")
## contract: check for published updates at startup and then every hour while online.
@export var refresh_hours := 1.0
## contract: first retry after a failed check, real minutes; it doubles after each failure (1, 2, 4 ...).
@export var retry_first_minutes := 1.0
## contract: the retry wait never grows beyond this, real minutes.
@export var retry_cap_minutes := 60.0
## engineering: timeout for one download when the bundle's refresh entry does not give one, seconds.
@export var default_timeout_s := 20.0
## engineering: largest download accepted when the refresh entry does not give a limit, bytes.
@export var default_max_bytes := 2000000

@export_group("Game Ls from the sol count")
## game transformation: solar longitude (degrees) of sol 0 of a new game. Below 0 = the start of the archive's
## observed season (the earliest ls_start in the bundle), so a new colony begins in the season the data covers.
@export var start_ls := -1.0
## S01 (Mars Fact Sheet: orbital period 686.98 Earth days) with S02 (sol length): one Mars year is about 668.6 sols.
@export var mars_year_sols := 668.6
## S01 (Mars Fact Sheet: orbit eccentricity 0.0935): used in the equation of the centre.
@export var orbit_eccentricity := 0.0935
## physics (standard orbital element of Mars): solar longitude of perihelion, about 251 degrees.
@export var ls_perihelion_deg := 251.0

@export_group("Sky")
## game transformation: the archive's opacity is multiplied by one factor so that the sky at the start of a new game
## equals GameBalance.dust_tau_default; the seasonal shape and the episode curves keep their archive proportions.
@export var scale_sky_to_default := true
## balance: the opacity the game ever uses is bounded to this (no sky darker than this).
@export var max_tau := 4.0

@export_group("Teach before escalation")
## contract: no dust event before the colony has run this many sols (and the panel response has been taught).
@export var teach_min_sols := 2.0
## balance: the first event starts this many game hours after the teaching condition (at least), range.
@export var first_gap_hours_min := 6.0
@export var first_gap_hours_max := 14.0
## balance: the first event is minor: its severity scale is at most this (and it uses the archive's smallest episode).
@export var minor_severity_max := 0.35
## balance: the first event's severity scale is at least this.
@export var minor_severity_min := 0.22

@export_group("Gaps, duration, severity (game transformation)")
## game transformation (accelerated interval, not NASA-observed storm frequency): calm sols between the end of one
## event and the start of the next, drawn per seed between these.
@export var gap_sols_min := 1.0
@export var gap_sols_max := 4.0
## game transformation: shape of the gap draw (above 1 = short gaps more common).
@export var gap_shape := 1.4
## game transformation: an episode's observed duration is stretched by a factor drawn between these.
@export var stretch_min := 0.75
@export var stretch_max := 1.35
## game transformation: severity scale = share of the episode's observed opacity rise above its own background.
## Each later event may be stronger by this much (escalation), up to severity_max.
@export var severity_step := 0.25
@export var severity_max := 1.25
## game transformation: a non-first event uses at least this share of its escalation ceiling.
@export var severity_low_share := 0.45

@export_group("Readiness")
## balance: severity cap when the colony is least ready (battery near the reserve, cleaner broken, dusty panels,
## a life-support problem) and when it is fully ready; the cap is set when the warning is issued.
@export var readiness_cap_low := 0.4
@export var readiness_cap_high := 1.25
## balance: life-support battery reserve, kWh. About one night of control, heating, scrubber, fans and recycler.
@export var battery_reserve_kwh := 120.0
## balance: at least this many game hours between the end of one event and the start of the next; a colony that
## is not ready waits up to twice as long (the recovery interval varies with readiness).
@export var recovery_hours_min := 18.0
## balance: an event is held back while the battery is below this many times the reserve or an urgent life-support
## alert is active, re-checked every `hold_hours`.
@export var hold_battery_factor := 1.5
@export var hold_hours := 6.0
## balance (dust management before escalation): after the first, minor event, the next one is also held while the
## panels are at least this dusty on average and the cleaner does not work (dust a storm leaves on uncleaned panels
## would otherwise stay and push the colony into a lasting power deficit).
@export var hold_dust := 0.2
## balance: weights of the four readiness parts (battery, cleaner working, clean panels, life support), sum 1.
@export var readiness_weights := Vector4(0.35, 0.25, 0.25, 0.15)

@export_group("Warning and return margin")
## contract + balance: a warning comes at least this many times the longest current outdoor walk home before the
## opacity starts to rise.
@export var return_margin := 2.0
## balance: and never less than this many game hours before the event.
@export var min_warning_hours := 4.0
## engineering: future events kept in state.weather_queue.
@export var queue_length := 3
## engineering: past events summarised in state.weather.history.
@export var history_length := 12

@export_group("Walking routes (ReturnRoutes)")
## engineering: route grid cell, metres.
@export var route_cell_m := 2.0
## balance (PlayerTuning.max_slope_degrees): steeper ground cannot be walked.
@export var route_max_slope_deg := 40.0
## balance: walking cost = distance x (1 + this x slope grade), so slopes take longer.
@export var route_slope_penalty := 1.0
## physics of the player body (PlayerTuning.body_radius_m): obstacles are grown by this, metres.
@export var route_body_radius_m := 0.22
## balance: obstacles lower than this above the ground can be stepped over (PlayerTuning.step_height_m), metres.
@export var route_step_m := 0.25

@export_group("Presentation")
## balance: sun light at the darkest sky is never less than this share of normal.
@export var sun_min_share := 0.25
## balance: sky brightness never less than this share of normal.
@export var sky_min_share := 0.35
## balance: fog density added per unit of opacity above the default, and its upper bound.
@export var fog_density_per_tau := 0.006
@export var fog_density_max := 0.02
## balance: how quickly the shown sky follows the opacity (1/s); the opacity itself is already smooth.
@export var sky_follow_rate := 0.8
## balance: most dust particles drawn near an outdoor player.
@export var dust_particles_max := 160
## balance: opacity above the default where outdoor dust particles start.
@export var dust_particles_from_tau := 0.25
