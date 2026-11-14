Created:
- `scripts/player/player_controller.gd`
- `scripts/player/player_camera_rig.gd`
- `scripts/player/player_input.gd`
- `scripts/player/player_tuning.gd`
- `scripts/player/player_visual.gd`
- `scripts/player/carry_item.gd`
- `tests/test_player.gd`

Exact test command:

```powershell
..\godot.cmd --headless --path . --script res://tests/test_player.gd --log-file 'G:/nasa app/_work/wD/tests/tmp/player.log'
```

Full last output:

```text
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
PASS input move_forward
PASS input move_back
PASS input move_left
PASS input move_right
PASS input sprint
PASS input jump
PASS input interact
PASS input grab
PASS input toggle_view
PASS input map
PASS input push_to_talk
PASS input back
PASS input source_register
PASS F5 unbound
PASS view and map separate
PASS grab help
PASS ensure preserves remap
PASS remap save reset load
PASS capsule and collision layers
PASS Mars free fall 1.3000 s
PASS jump apex 0.2204 m airtime 0.7000 s
PASS walk speed 3.0000 m/s
PASS suit speed 2.4000 m/s
PASS sprint ratio 1.6000
PASS local sprint stamina drains
PASS climbs 20 degree ramp
PASS rejects 50 degree ramp
PASS climbs 0.2 m step
PASS wall blocks for two seconds
PASS starts first person
PASS first person FOV
PASS first person head hidden limbs visible
PASS zone layers preserve hidden head
PASS third person FOV and distance 2.500 m
PASS camera stays before wall
PASS spring arm sphere and mask
PASS one current camera true
PASS one current camera false
PASS look and pitch clamp
PASS 20 view toggles and suit preserve authority
PASS map never toggles perspective
PASS aim identifies item
PASS grab sends one pickup and attaches
PASS held item follows hand within 1 cm
PASS drop sends once and restores free body
PASS controller never changes cargo or owner
PASS refused pickup attaches nothing
PASS refused drop keeps prop held
PASS sprint drop throws forward
PASS suit station dispatch
PASS other station returns host failure
PASS four distinct identity patches
PASS both hand anchors exist
PASS visual state idle
PASS visual state walk
PASS visual state sprint
PASS visual state jump
PASS visual state land
PASS visual state carry
PASS visual state use
PASS visual state suit
PASS visual state seated
PASS suit toggles helmet and pack
PASS replacement model anchors and head layers
PASS position reported every physics frame
RESULT 65/65
```

Deviations/limitations: Godot’s native `Node3D.set_identity()` conflicts with the requested method. The implementation uses an optional index and requires `visual.call("set_identity", index)`. The engine certificate-store error remains; there are zero script errors or warnings-as-errors. Exit code: 0.