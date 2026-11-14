# Mars Colony — Preserved source manifest (original Blender files)

Prompt 17 requires that the original Blender source is preserved and its hash unchanged. This manifest lists every
`.blend` / `.blend1` file under `G:\nasa app` (excluding `_work\` copies and `.git\`), hashed on **2026-11-14** with
PowerShell `Get-FileHash -Algorithm SHA256` (read-only; no file was opened, moved or written).

Baseline: `G:\nasa app\mars_colony_godot\docs\milestones\01_audit\evidence\hashes_before_after.csv` (Prompt 01,
2026-11-11; the same values are in `docs\milestones\01_audit\inventory.md` section 3, and Prompt 02 reported them unchanged).

## 1. Original sources with a recorded baseline — 14 of 14 match

| # | Path (under `G:\nasa app\`) | Bytes | SHA-256 now (2026-11-14) | Baseline (P01) | Result |
| --- | --- | ---: | --- | --- | --- |
| B1 | `grand_colony\grand_colony.blend` (main colony scene, saved with Blender 5.3) | 219,541,930 | `6AAD006F0CA604DDF263E644D046F19E53F9B093082EBC3EBFB90D0CD15C916B` | same hash, same size | **Match** (see note 1) |
| B2 | `grand_colony\grand_colony.blend1` | 219,964,569 | `FEF31F232ECD93C53ED574480B9FD562BB53532F29C7642C6FEFD42CE91709B4` | same | **Match** |
| B3 | `grand_colony_drive\grand_colony.blend` | 219,940,169 | `A00D05EB063BA9BA1B03BC344D40EC8E89C8772229ECBF8D171BB4EB18A40D10` | same | **Match** |
| B4 | `mars_kit\mars_kit.blend` | 12,634,045 | `AD277F210448BD890F5E41D87445B0613BB86CCDCEF8C391CA225A07BF274B32` | same | **Match** |
| B5 | `backup_before_claude_colony.blend` | 495,216 | `8E043A750961B9E26927E0BF503CEE80BCAF95AEC4D320CD23B4800B9EB98B84` | same | **Match** |
| B6 | `grand_colony\work\_downloads\human_base_meshes\extracted\human-base-meshes-bundle-v1.4.1\human_base_meshes_bundle.blend` | 49,420,489 | `3C121505651140CEB4D69FD1D8923F7788FFADD81672F5BE14845A5F2C75C137` | same | **Match** |
| B7 | `grand_colony\work\_v12\k1\kit.blend` | 575,531 | `F1D28096D7B665032937330C88319D030479EE3557659676E1FEC5223304DDBC` | same | **Match** |
| B8 | `grand_colony\work\_v12\k2\kit.blend` | 572,420 | `C48A60B3498D01DAFAA7F9184017E2A6595A38A58C127A1DCB339F049F70C8F1` | same | **Match** |
| B9 | `grand_colony\work\_v12\k3\kit.blend` | 572,153 | `EEA0DF938801C556DD34BDE7D0C6D5CA6446D8264D9713B7122D4151B91E45D4` | same | **Match** |
| B10 | `grand_colony\work\_v12\k4\kit.blend` | 570,828 | `3BE3601720F1D09E9B2C57C78E3763596EBE1C34EADF471AC08D0297D8B628FA` | same | **Match** |
| B11 | `grand_colony\work\_v12\k5\kit.blend` | 569,488 | `708A99C3B49133AB06CC09CDE120761768FD3661DD43854B7F219B8781686CDD` | same | **Match** |
| B12 | `grand_colony\work\_v12\t1\test.blend` | 13,329,150 | `ED5055DE99BD0E47ABFB4A7DE0D72DEFB98C9E6520ADAA70807B3184181E0595` | same | **Match** |
| B13 | `grand_colony\work\_v12\t2\test.blend` | 13,494,614 | `0D61588CE3BB0590DAE63ADEC6D2D012C502181D4260319A2B13152C88382681` | same | **Match** |
| B14 | `grand_colony\work\_v12\t3\test.blend` | 13,514,139 | `81C24F65E8818124F82649558DB23ECBE683E47525AB0F07B8A48AF18092B162` | same | **Match** |

**What matched exactly:** for all 14 files the full 64-character SHA-256 and the byte size are identical to the Prompt 01
baseline. The original Blender source, in particular `grand_colony\grand_colony.blend` (B1), is byte-for-byte unchanged.

Note 1. B1's last-modified time is now **2026-11-13 18:40:52**; the baseline recorded 2026-11-11 01:23:10. The content
hash and size are identical, so the bytes are unchanged; something rewrote or touched the file with identical content
(for example a copy back or a timestamp update). The cause was not investigated. All other 13 files keep their recorded
modification times.

## 2. Derivative Blender files (no baseline recorded)

These were made by the project (character rigs and variants, Prompts 04 onward) and live in the game repository's
`assets_src\`, which the export excludes. No earlier hash of them is recorded in the docs, so they can only be listed,
not compared. They are not original sources.

| Path (under `G:\nasa app\`) | Bytes | Modified | SHA-256 (2026-11-14) |
| --- | ---: | --- | --- |
| `mars_colony_godot\assets_src\characters\astronaut.blend` | 1,564,455 | 2026-11-11 09:00:38 | `07FA4F31BC9A970CF783C8E6CF20795033F5F93ADE35B8ED7C79EE5F8C6FA727` |
| `mars_colony_godot\assets_src\characters\astronaut_pre_mixamo_walk.blend` | 1,646,505 | 2026-11-11 08:58:55 | `D507FAA85051E8745965A5C149089DAB402D4E8EC46FCC802D9B53198466A056` |
| `mars_colony_godot\assets_src\characters\crew_v2\crew_v2.blend` | 1,340,986 | 2026-11-13 19:47:19 | `6969324CDEDEC452F6FAFA21639EC4755BD4BF8F8C511BC9E36424A84D3434BB` |
| `mars_colony_godot\assets_src\characters\crew_v2\crew_v2_work.blend` | 139,152 | 2026-11-11 09:06:23 | `89A8BA338FED25B4A0E0094550CB5847FCC10464F3E6DF60AD8CF80B9BE5CF4D` |
| `mars_colony_godot\assets_src\characters\crew_v2\variants_work\crew_v2_backup_before_variants.blend` | 1,233,728 | 2026-11-12 22:24:08 | `74410250B8A6AC0057D6059F584DB28FCAFC8F915CF1D49193C8806C561B7116` |

No other `.blend` file exists under `G:\nasa app` outside `_work\` and `.git\`.

## 3. Pinned build inputs (re-hashed 2026-11-14)

| File | Hash | Compared with | Result |
| --- | --- | --- | --- |
| `_tools\godot_4.7.2_templates\Godot_v4.7.2-stable_export_templates.tpz` (1,281,349,702 bytes) | SHA-512 `CA4D71C4D7B81DFC15D1A98BAA07534AA95B03FDDA78A0075B06672E1648D2E5F40980C9ADC28D23E1B92E732EE7BF3461997AA804AF74EC2FCD7A93CCB84079` | Official `SHA512-SUMS.txt` beside it | **Match** |
| `_tools\godot_4.7.2_templates\extracted\templates\windows_release_x86_64.exe` | SHA-256 `D34D36F3BE1A6C49C56525AE86469B92E4F417DDF0B43CF00DD80C385C4B0562` | none recorded | listed only |
| `_tools\twovoip_6.1\TwoVoIP_v6.1.zip` | SHA-256 `01825E1FB99B483FE6EF3B43A4578F6E5CF029AE6F39C292D99EB8AF3DD0D098` | `addons\twovoip\VERSION.txt` | **Match** |
| `addons\twovoip\libs\libtwovoip.windows.template_release.x86_64.dll` (6,465,024 bytes) | SHA-256 `C9F47DF2221B5EF196E1ECFA57E7C9289556D832441F2E6FA64E2E9B86FDFCBF` | none recorded | listed only |
| `addons\twovoip\libs\libtwovoip.windows.template_debug.x86_64.dll` (6,511,104 bytes) | SHA-256 `8E90F784E144FD1B0350FB9F322DA4FCFE5A01C01AC1B2313CD6DE763794CB44` | none recorded | listed only (not shipped in a release export) |

(The two DLLs were hashed in both the P17 docs working copy `G:\nasa app\_work\p17d` and the live project
`G:\nasa app\mars_colony_godot\addons\twovoip\libs\`; the values are identical.)

## 4. Not covered here

- The other non-`.blend` source files of the Prompt 01 baseline (the 6 "other source files" in the P01 handoff) were not re-hashed in this pass.
- `grand_colony` still has uncommitted v12 work (issue I-21); its git state was not changed or inspected here.
