# Prompt 01 — Source and authority matrix

Audit date: 2026-11-11. This table says which input governs what, whether it was available to this milestone, and how it may be used. Precedence follows the shared brief: the three product documents are the default authority; an explicit owner decision made after a question overrides a conflicting document requirement; the browser game and the Godot port are implementation evidence only.

## 1. Inputs

| ID | Input | Authority | Governs | Available? | Used in this milestone |
| --- | --- | --- | --- | --- | --- |
| A1 | `Mars_Colony_Master_Plan.docx` | Governing | Full context | **No.** Not in `G:\nasa app`, not in the Downloads folder. | Not read. |
| A2 | `Mars_Colony_Product_Brief.docx` | Governing | Scope and validation | **No.** Same search. | Not read. |
| A3 | `Mars_Colony_PR_FAQ.docx` | Governing | Player promise | **No.** Same search. | Not read. |
| A4 | `Mars_Colony_Execution_Prompt_Pack.docx` (SHA-256 `27C840F9…BB3E3E`) | Shared brief, engineering contract, common execution instruction, prompts | Product rules recorded from the owner's earlier conversation; stack; acceptance methods | Yes, in Downloads | Read through page 12 only, on the owner's instruction (decision D-01). |
| A5 | Owner decisions after a question | Overrides A1–A3 where they conflict | Whatever the decision names | The earlier conversation is not available; its decisions are known only as recorded in A4. Three instructions were given in this session (D-01 to D-03). | Recorded in `docs\decisions.md`. |
| A6 | Improved map with its source Blender scene | Owner-supplied world | Final geometry, cameras, lighting references | **No. Not supplied.** | Requested (issue I-02). |
| A7 | Browser game (`grand_colony\game\`) | Implementation evidence | Nothing. Baseline of working behaviour and of what is superseded. | Yes | Inspected and self-tested. |
| A8 | "Existing Godot port" with tests and reports | Implementation evidence | Nothing. Starting point to extend. | **Not found in the workspace.** Only the two LAN Walk prototypes exist. | Contradiction C-01. |
| A9 | `grand_colony\grand_colony.blend` (B1) and its saves B2, B3 | Source asset to preserve | Current authored world, cameras, lights, materials | Yes | Audited read-only. |
| A10 | 15 Cycles beauty shots and contact sheet (2026-11-08) | Style and fixture reference | Nothing for parity once geometry changes | Yes | Reviewed. Not re-rendered. |
| A11 | `grand_colony\refs\` (120 images) | Visual reference | Nothing | Yes | Listed. |
| A12 | Blender Studio Human Base Meshes 1.4.1 | Third-party asset | Possible base for derivative character rigs | Yes | Audited. Licence note in section 3. |
| A13 | `cinematic\` | Out of scope | Nothing (video and cutscenes are excluded) | Yes | Listed only. Canon mismatch noted (C-04). |
| A14 | `mars_kit\` | Earlier study | Nothing unless the owner approves its assets | Yes | Audited. |
| A15 | Primary NASA, PDS and engine references | Scientific and technical authority | Facts, units, API behaviour | Online | Checked; see `docs\source_register.md`. |

## 2. What "confirmed", "proposed", "open" and "deferred" mean here

Prompt 01 asks for the product documents to be read and their material classified. A1–A3 are missing, so that classification could not be done from the documents. The classification below is therefore limited to what the pack itself records on pages 1 to 12.

| Class | Meaning in this audit | Where listed |
| --- | --- | --- |
| Confirmed | Stated as a rule or decision in the shared brief or engineering contract (pack pages 2–11 as rendered). | `docs\requirements_matrix.md` — 62 requirements. |
| Implementation default | The pack labels it a tunable default, not a product decision (for example tier labels 0–3, 5 Hz tick, 72° FOV, 2.5 m camera distance, 20% suit slowdown, sol range 5–120 min). | Flagged "default" in the requirements matrix. |
| Open | Needs an owner answer or a missing input before work that depends on it. | `docs\issues.md`, `contradictions.md`. |
| Deferred or excluded | The pack excludes it: new buildings, free placement, terrain editing, extra sectors, autonomous inhabitants, tasks needing simultaneous players, video and cutscenes, NPCs, host migration, accounts, matchmaking, web frameworks, cloud databases, analytics, AI runtime services, image generation in ordinary gameplay. | Section "Exclusions" of the requirements matrix. |
| Proposed (catalog-only) | Ideas in the product documents' research catalogs that were never approved. | **Cannot be listed: A1–A3 are missing**, and the pack's own list of deferred ideas sits after page 12. |

## 3. Third-party assets and licences found

| Asset | Where | Licence evidence found | Status |
| --- | --- | --- | --- |
| Blender Studio Human Base Meshes 1.4.1 | A12 | The `README` text block inside the `.blend` says "All provided assets are public domain under the CC0 license." A second text block named `License` says "The Rain Rig is released under the Creative Commons Attribution 4.0 license. The attribution is © Blender Foundation \| cloud.blender.org". | **Ambiguous inside the file.** The `License` block names a different product (Rain Rig) and looks like a leftover, but it was not resolved against the publisher's page. Until it is, credit "Blender Foundation / Blender Studio" wherever a derivative is used. Issue I-12. |
| three.js r160, cannon-es 0.20.0 | Loaded from jsDelivr by the browser game | Not checked in this milestone | Browser demo only. Not a dependency of the Godot game. |
| Funplay MCP add-on | Outside the workspace | Not checked | Tooling only. Must not ship in the game. |
| Reference images in `refs\` | A11 | The README calls them visual references; no licence file | Reference only. Do not ship. |

## 4. Authority conflicts found

All conflicts are in `contradictions.md`. The ones that change what a later milestone may do are C-01 (no Godot port), C-02 (governing documents missing), C-03 (Godot editor project outside the workspace), C-05 (survivor NPC), C-06 (rover seats) and C-09 (spawn location).
