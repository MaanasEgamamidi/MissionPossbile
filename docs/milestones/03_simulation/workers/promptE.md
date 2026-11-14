You are building the player character asset for a Godot 4.7.2 game (a cooperative Mars colony game for ages 9 to 12).
Work in the current folder (the project workspace). Blender 5.3 is installed as a Microsoft Store app.

HARD RULES
- NEVER save, overwrite, move or modify any existing .blend file or any other existing file in this workspace.
  Create new files only, and only under these folders:
    mars_colony_godot\tools\blender\character\   (your scripts)
    mars_colony_godot\assets_src\characters\     (the new .blend you build)
    mars_colony_godot\assets\characters\         (the exported GLB)
    docs\milestones\04_player\rig\               (notes, pose images, logs, JSON report)
- Do not run Godot. Do not touch any other folder (other workers are busy in _work and mars_colony_godot\scripts).
- Run Blender only headless, the way mars_colony_godot\tools\export_from_blender.ps1 does it (read that file first):
  blender-launcher.exe under %LOCALAPPDATA%\Microsoft\WindowsApps, arguments -b --factory-startup --disable-autoexec
  --python <script> -- <args>, started with Start-Process -Wait. The launcher prints nothing to the console, so your
  Python must write its own log file and a JSON report. Start from the factory scene and bring source data in with
  bpy.data.libraries.load(path, link=False); never open a source .blend and save.
- If Blender cannot be started from your sandbox, write the scripts as completely and carefully as you can, state
  clearly in the final message that they are untested, and stop.
- No image textures and no texture baking. Materials are plain Principled BSDF values.

SOURCES (read-only)
- Human body: grand_colony\work\_downloads\human_base_meshes\extracted\human-base-meshes-bundle-v1.4.1\human_base_meshes_bundle.blend
  (Blender Studio Human Base Meshes 1.4.1; 227 meshes, no rig, no materials). List the object names and choose one
  realistic full-body base mesh in a neutral A or T pose.
- Spacesuit: object qt_spacesuit in grand_colony\grand_colony.blend (a single wall-stowed EVA suit: 86,524 triangles,
  18 materials, 73 loose parts, 0.72 x 0.52 x 1.88 m, static mesh, procedural materials; there are two instances, use one).
  Do not use al_suit_rack (three suits fused with a rack).
- docs\milestones\01_audit\asset_readiness.md section 6 describes what exists.

DELIVERABLE
mars_colony_godot\assets\characters\astronaut.glb, and the scripts that rebuild it from the sources with one command:
mars_colony_godot\tools\blender\character\build_character.ps1

REQUIREMENTS
1. One armature object named Armature: a humanoid about 1.8 m tall standing at the origin, feet on z = 0, facing
   Blender -Y. Bone names exactly (no dots): Hips, Spine, Chest, Neck, Head, ShoulderL, ShoulderR, UpperArmL, UpperArmR,
   LowerArmL, LowerArmR, HandL, HandR, UpperLegL, UpperLegR, LowerLegL, LowerLegR, FootL, FootR, ToesL, ToesR, plus two
   helper bones parented to the hands at the palm: HandAnchorL, HandAnchorR (for holding items).
2. Body: the base mesh reduced to at most 20,000 triangles, skinned with automatic weights, and split into separate
   mesh objects by region so the game can hide parts: Body_Head (head and neck), Body_Torso, Body_Arms (arms and hands),
   Body_Legs (legs and feet). The person must read as a clothed crew member, never as an undressed body: material
   Mat_Coverall (a plain indoor coverall) on torso, arms to the wrist and legs; Mat_Skin on head and hands; Mat_Boot on
   feet; Mat_Hair as a simple hair cap. Add a small shoulder patch and a chest stripe with their own material Mat_Ident
   (the game recolours it per specialist).
3. Suit: from qt_spacesuit, scaled and placed to enclose the body. The person must fit inside the suit: check it
   numerically in the rest pose (for example nearest-surface or ray tests from body vertices) and report the percentage
   of body vertices outside the suit for torso, arms and legs. Split the suit into its loose parts, give each part a
   rigid weight of 1.0 on the nearest sensible bone, then join into Suit_Helmet (helmet and visor), Suit_Torso (with
   backpack), Suit_Arms (with gloves), Suit_Legs (with boots). At most 45,000 triangles for the whole suit. Replace the
   procedural materials by plain Principled BSDF colour, roughness and metallic values; the visor is a dark, slightly
   transparent material Mat_Visor. When the suit is worn the game hides Body_Torso, Body_Arms and Body_Legs.
4. Animations, one Action each, exported as glTF animations with exactly these names, 30 fps, in place (no root
   motion), made by code from key poses:
   idle (loop, 4 s, slight breathing sway), walk (loop, about 1.0 s cycle, relaxed low-gravity gait),
   sprint (loop, about 0.7 s), jump (0.4 s, crouch to take-off pose, hold the last frame), land (0.4 s),
   carry (loop; both forearms raised as if holding a box in front of the chest; legs neutral),
   use (1.0 s; the right hand reaches forward to a panel at chest height and returns),
   suit (1.0 s; a self-check gesture: hands to chest and helmet seal and back),
   seated (static pose sitting on a 0.45 m seat, hands on thighs).
   Feet must not go below the ground; limbs must not pass through the torso.
5. Export one GLB (+Y up) containing the armature, all Body_ and Suit_ meshes and all nine clips. Verify by importing
   the GLB into an empty factory scene and writing the bone names, mesh names with triangle counts, materials and
   animation names with lengths into docs\milestones\04_player\rig\report.json.
6. Evidence, cheap to make (Workbench or EEVEE, 640 x 800): for idle, walk, sprint, jump, carry, use, suit and seated, a
   front and a side still at a representative frame, once with the suit and once without, in
   docs\milestones\04_player\rig\poses\. Look at them yourself and fix obvious breakage (limbs through the body,
   exploded weights, suit parts left behind).
7. docs\milestones\04_player\rig\PROVENANCE.md: exact sources (file, object names, the licence text as found in the
   bundle's own licence or readme file - give the path you read), every processing step with numbers (triangles before
   and after, suit scale, body-outside-suit percentages, bone list, clip list with lengths), what was checked by a
   script and what by looking, and an honest defect list. Claim nothing you did not check.

FINAL MESSAGE: files created, the command that rebuilds everything, the key numbers from report.json, the defect list.
