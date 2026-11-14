# C01-C04 cassette handoff

This batch implements the newly authorized cassette section (PDF pages 18-21), following the completed F01-F06 foundations on `revisions`. The source/briefing appendix on pages 54-57 is reference data. Stop before S01; actual repair puzzles, faster deterioration, lethal timing, restoration art and cinematics remain outside this batch.

## Execution ledger

| Unit | Dependencies | Owner | Current status |
| --- | --- | --- | --- |
| C01 six shared cassette pickups | F03, F04, F06 | Foundation engineer | Complete; host/presentation checks 88/88. Six real world pickups and target removal covered in the final 113/113 rendered walkthrough. |
| C02 Command Room player | C01, F05 | Foundation engineer, UI engineer | Complete; final UI checks 76/76, including useful-pane-size, contrast and actual keyboard scrolling checks. Reader authorization covered by real ENet 56/56. |
| C03 NASA photographs and provenance | C01 | Parent integrator | Complete; six local photographs and matching official source/credit records packaged, asset checks 57/57 and actual offline PCK verification 6/6. All six image files visually reviewed independently by the orchestrator. |
| C04 six room briefings | C02, C03, T01-T12 designs | Parent integrator | Complete within the user-approved preview adjustment: two pages each, 169-178 words. No T puzzle controls or S timing are advertised as current. |

The parent coordinates source control, integration, NASA assets/content and final checks. The orchestrator coordinates contracts, security review, ENet verification and this handoff. The foundation specialist owns pickup/player authorization and world/inventory behavior. The UI specialist owns the player frame and input/accessibility checks. The runtime supports three child agents; no additional child can be created while these slots are occupied.

## Product and security contracts

- Exactly six shared library identities: `cassette_command_center`, `cassette_power_supply`, `cassette_greenhouse`, `cassette_green_dome`, `cassette_med_bay`, `cassette_hangar`. Indoor Greenhouse and exterior Garden dome remain distinct.
- Pickups reveal title and collection status only. Inventory lists collected/missing titles and the instruction "Play at Command Room cassette player." Cassette collection uses no cargo slots and never exposes briefing content in inventory or pickup UI.
- Exactly one instructional reader: established `cassette_player_command_center`, physically in `Command Room`. It works before room repairs. Host validation applies to opening, selecting another tape and page navigation, with actual ownership, station identity/kind, reach and Command Room location checked.
- A pending network request does not authorize showing content. Client-controlled completion/access flags cannot substitute for host validation. Critical warning, death/recovery, disconnect, station invalidation or loss of reach closes playback safely; survival and other players continue.
- Shared collection is additive/idempotent. Repeated requests and competing peer pickups create one library entry. Collected physical tapes disappear for all peers and late joiners; their props remain non-solid.
- The reader uses a centered two-column rectangular frame, initially about 82% viewport width and 76% height, with world margins visible on all sides/corners. NASA photo is left; briefing text is right. Maintain aspect ratio, scrolling, keyboard navigation, captions, credits/source links and a reachable Close control.
- NASA files are local/offline. Every image needs matching official page, original asset URL, image ID when available, accurate caption, creator/credit, access date and restriction/crop notes. ISS and ground-test photographs must be labeled accurately, without presenting them as photographs of a real Mars colony.
- Source-register entries may contain factual NASA photograph/provenance descriptions. Full gameplay briefing text stays in the Command Room reader to preserve the reading restriction.
- No voice narration is required or introduced.

## Scope dependency decision

C04 asks for roughly 120-180 words per room, naming actual implemented controls and success cues for both tasks. Its stated dependencies include T01-T12 designs. The current project has host task foundations and reserved anchors, but no production puzzle validators or controls. The appendix seeds describe future mechanics and a future four-second hazard. Those sentences cannot be shipped as claims about current behavior.

The user explicitly chose to stay within C and ship truthful preview briefings, without implementing T. Current collection/player controls can be explained concretely; future task designs are clearly labeled previews. The PDF's original acceptance requirement that a player learn the first input and completion condition of all twelve implemented puzzles remains deferred to their later implementation. This is a user-approved scope adjustment, not an unreported completion claim. S01's future four-second timing is not described as current gameplay.

## Verification

Final current cassette verification passes **17 affected suites, 1261/1261 checks**, with zero FAIL/SCRIPT ERROR/Parse Error lines in the selected newest per-suite logs. `CASSETTE_VERIFICATION.md` records the exact matrix, evidence paths, source-selection method and corrected initial test-fixture/type failures. This total does not add the historical F batch's 2042 checks.

Compilation reports 258 scripts OK; actual exported PCK metadata/texture loading passes 6/6 offline. The corrected real-world suit approach repeats 10/10 in a focused run, separately from the 33/33 complete game-scene suite; the overlapping repeat is not added to 1261. Final rendered local approaches/collection/playback pass 113/113. No required C01-C03 implementation remains incomplete; C04's deferred production-puzzle instructions are explicitly covered by the user-approved preview scope.

## Changed paths and public APIs

- `scripts/cassettes/cassette_catalog.gd` owns the six stable title/room identities and validates local briefing/photo availability. `cassette_actions.gd` registers the host action definitions. `cassette_runtime.gd` owns transient, nonexclusive reader authorizations. `cassette_presenter.gd` creates six original native cassette models and one native player, without solid collision.
- `scripts/session/session_service.gd` prunes/releases readers on motion, death/recovery, crew release and session changes; its existing session replica carries live reader records. `scripts/game/game_main.gd` connects E on a cassette pickup to collection and installs the presenter before the merged performance rig pins runtime render layers.
- `scripts/ui/cassette_player_panel.gd` and `cassette_library.gd` implement authorized image/text playback. `inventory_panel.gd` exposes six metadata-only collection rows. `station_panels.gd` routes the sole player station to the reader; reserved pickup panels retain metadata-only fallback behavior. `UiPanel` adds optional viewport fractions and critical interruption; `UiRoot` honors them. Existing `TaskPanel` explicitly retains critical interruption behavior.
- `data/cassette_briefings.json` holds the two-page preview records; `cassette_photos.json` records official pages/original URLs, identity, captions, credits, restrictions, hashes, dimensions and processing. `sources_cassettes.json` and `credits.json` integrate provenance with the existing source register. The six optimized JPEGs are under `assets/cassettes/`.
- New behavioral suites are `tests/test_cassettes.gd`, `test_cassette_ui.gd` and `test_cassette_assets.gd`. Existing ENet and full-map anchor suites add cassette integration coverage. Legacy station/LAN/P07 panel tests recognize the new authorized reader contract. `test_saves.gd` isolates its save-integrity fixture from unrelated export artifacts. `test_game_scene.gd` retains all original suit assertions, corrects its capsule-placement fixture and adds a grounded/reported/reach assertion plus a repeatable `--suit-only` mode.

Actions use the existing host `ActionService`:

| Action | Target | Parameters | Authoritative effect |
| --- | --- | --- | --- |
| `cassette_collect` | `cassette_<room_id>` | None | Adds one shared collected ID; returns title/status metadata only. |
| `cassette_open` | `cassette_player_command_center` | None | Authorizes this actor/peer at the physical player; no tape content is returned. |
| `cassette_select` | Same player | `cassette_id: String` | Selects one collected tape at page 0 after fresh validation. |
| `cassette_read` | Same player | `cassette_id: String`, `page: int` | Authorizes an existing page of the currently selected tape after fresh validation. |
| `cassette_close` | Same player | None | Releases only the requesting peer's reader; allowed while paused and after leaving reach. |

Runtime reader records in `SessionService.cassette_runtime.readers[str(peer)]` contain `station_id`, `actor_id`, selected `cassette_id` and `page`. Their serialized session replica is `session.cassettes.readers`; they never enter disk saves. Collection continues to use the established `ColonyState.repair.collected_cassettes` field, so no save-envelope/protocol bump is needed. Older foundation saves start with the same empty/default collection state; known collected IDs survive normal restore.

The player clears its old photograph/text immediately when a host request becomes pending. It renders local content only after the answer agrees with the current reader's station, actor, tape/page and current local reach/room. A cached successful request from an earlier position cannot restore a revoked reader. The authoritative host does not send instructional text in action responses.

## Photographs and preview content

| Room | Official image identity | Visible credit | Briefing pages / words |
| --- | --- | --- | --- |
| Command center | `iss073e0252501`, ISS ham-radio communications | NASA | 2 / 170 |
| Power supply | `ISS038-E-042665`, ISS solar arrays above Earth | NASA | 2 / 172 |
| Indoor Greenhouse | `iss064e004220`, ISS radish growth chamber | NASA/Kate Rubins | 2 / 177 |
| Garden dome | `30795688500_ed64d9f74b_o`, Kennedy ground development unit | NASA/Bill White | 2 / 177 |
| Med Bay | `ISS036-E-035750`, ISS ultrasound research | NASA | 2 / 178 |
| Hangar / airlock | `iss064e013338`, Quest spacesuit/tool staging | NASA | 2 / 169 |

Word counts combine each briefing's two pages and exclude its separate photograph caption/credit. Every record is marked `briefing_status: preview`, and the reader visibly labels the planned repair content. The power photograph replaces the appendix's ESA/NASA-credited candidate with a NASA-credited ISS photograph; the rationale is preserved in the source manifest. No local crop or creative image edit is applied. These are photographs of ISS hardware or an Earth prototype, not an operating Mars colony.

## Evidence and limitations

`evidence/cassettes/` contains all six photo/briefing combinations, normal 720p/1080p readers, enlarged/high-contrast layouts and scrolled controls, inventory metadata, a collected/missing library popup and critical interruption. Independent review of the updated captures confirms readable tape selection, useful non-collapsed photo/text panes, separate scrolling, a fixed Close button and visible world corners. The popup shows three real collected entries and three disabled missing entries without opening a briefing. Initial capture issues (MenuButton color and a collapsed content region at maximum scale) were corrected; meaningful pane-size and contrast assertions were added, together with keyboard scrolling checks.

`evidence/cassette_world/` records each of the six physical tapes before and after actual collection, the native Command Room deck before use and its opaque reading frame. Independent review of the before/after contact sheet and final deck/reading captures confirms distinct room labels, visible original cassette models, disappearance after collection with metadata-only feedback, readable caption/credit/source and world corners. The native props create no solid collision body.

The real ENet test submits competing host/client collection requests before yielding, verifies one winning shared entry, reconstructs collected IDs for late join, refuses direct open/select/read away from the player, validates selection/page changes, and checks movement revocation and closed playback after reconnect. No human or two-computer playtest is claimed.

The earlier remote-main/cassette checks exposed four cascading suit-test failures. Actual diagnostics later showed the test fixture had placed the body at y=2.509 m and 2.93 m from the rack, so the host correctly refused it beyond the unchanged 2.6 m limit. Its search capsule was shorter/higher than the actual player placement and could miss geometry. The fixture now probes actual PlayerTuning dimensions with a conservative margin, uses the existing measured clear rack approach and asserts grounding/report/reach. Full corrected suite: 33/33; repeat suit-only fixture: 10/10. All original timing/tank/cancellation assertions remain; no production validator or gameplay rule was weakened. The performance rig explicitly exits without the map used in that test.

New room puzzles, four-second exposure timing, faster wear, restoration art and cinematics remain deferred. The C04 preview adjustment above is explicit and user-approved. Godot Vulkan renderer indexing/softshadow diagnostics and resource warnings were observed during rendered setup/teardown; no clean comparison proves they are pre-existing, and a warning-free renderer is not claimed. Exact diagnostics, successful exits and test-fixture corrections are reported in `CASSETTE_VERIFICATION.md`.
