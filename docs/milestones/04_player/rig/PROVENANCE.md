# Player character provenance

Status: verified_with_documented_limitations; Blender 5.3.0; coordinate system: Blender Z up, facing -Y; GLB +Y up.

## Exact sources
- `G:\nasa app\grand_colony\work\_downloads\human_base_meshes\extracted\human-base-meshes-bundle-v1.4.1\human_base_meshes_bundle.blend` :: `GEO-body_male_realistic`, realistic full-body A pose.
- `G:\nasa app\grand_colony\grand_colony.blend` :: `qt_spacesuit`, one instance. `al_suit_rack` is not loaded.
- Read-only references: `docs/milestones/01_audit/asset_readiness.md`, section 6, and `mars_colony_godot/tools/export_from_blender.ps1`.
- Appended into a factory scene via `bpy.data.libraries.load(path, link=False)`; source scenes never opened or saved.
- Source object names are listed in this run report and `../source_inventory_v2.json`. The supplied bundle actually yielded 407 object names / 382 meshes, differing from the old 227-mesh audit.

## Licence text found in the bundle
Path read: `G:\nasa app\grand_colony\work\_downloads\human_base_meshes\extracted\human-base-meshes-bundle-v1.4.1\human_base_meshes_bundle.blend` â†’ embedded Text datablock `README`. ZIP and extracted-file inventories had no separate README/licence file.
```text
Important Info
==============

Human Base Meshes: Asset Bundle - Version 1.4

All provided assets are public domain under the CC0 license.
The minimum supported Blender version is 4.2!

What's included
==============

These are various human base meshes that are provided by the Blender community and the Blender Studio.
They include:
    - Quad topology for multi-resolution sculpting
    - Closed volumes for voxel remeshing
    - Face sets
    - UV maps (including UDIMs)
    - Multiresoluton levels for realistic assets
    - Creased edges and Subdiv modifiers for planar/primitive assets

How to install the Asset Bundle
===============================

It's recommended to create a new Asset Library in the preferences first:
- Open the Preferences
- Go to "File Paths"
- Add a New Asset Library with the + button and call it "Human Base Meshes"
- Set the "Import Method" to "Append"

To add the assets from this file to the Asset Library:
- In the Asset Browser below, click on "Copy Bundle to Asset Library"
- Choose a target Asset Library
- Choose a target folder location

That's it. Enjoy!
```
Also read `G:\nasa app\grand_colony\work\_downloads\human_base_meshes\extracted\human-base-meshes-bundle-v1.4.1\human_base_meshes_bundle.blend` â†’ embedded Text datablock `License`:
```text
LICENSE

The Rain Rig is released under the Creative Commons Attribution 4.0 license. 
The attribution is Â© Blender Foundation | cloud.blender.org
```
The README states CC0 for the provided assets. The separate License text names the Rain Rig and CC BY 4.0; its applicability to this mesh was not independently established. No licence for the colony suit was established in this task.

## Processing
1. Removed modifiers and shape keys from the appended body; normalized the base to 1.800 m. Inflated clothed regions by 8 mm, relaxed the mesh, and shaped the torso into a plain coverall. Decimated before automatic heat weights; cut collar and cuffs; assigned constant coverall/skin/boot materials.
2. Used ARMATURE_AUTO on the complete body, checked weight coverage, then split into Body_Head, Body_Torso, Body_Arms and Body_Legs. Added a scalp hair cap, raised collar, curved specialist chest stripe, shoulder patch and closed rounded boots; underlying bare foot faces removed.
3. Split qt_spacesuit into 73 loose parts. Removed 10 wall-stand/mounting pieces (exact indices in report). Divided long sleeves and trousers at elbow/knee planes, then mapped source segments to the body joints with recorded length scales and radial scale 1.4. Kept each resulting piece rigidly weighted to one bone. Boots use a separate recorded fit: source-centred X Ã—1.7, Y Ã—1.25, Z Ã—1.15; centres X Â±0.21, Y +0.04. Tailored source gloves into closed convex mittens using body-hand clearance.
4. Reduced source suit pieces to approximately 48% (small pieces have a 20-triangle target floor). Added a simple life-support backpack, spherical overlapping elbow/knee/hip covers and 8 mm pressure liners. Liners are actual exported geometry, each a rigid convex shell enclosing its assigned body region. Sole clearance is clamped at z=0. These additions are included in the final suit budget.
5. Replaced procedural materials with constant Principled BSDF values. Mat_Visor: dark blue-green, alpha 0.88, roughness 0.18, metallic 0.4. No images or baking. Mat_Ident is shared by patch and chest stripe for recolouring.
6. Created 23 named bones, including hand-parented palm anchors. Authored nine actions at 30 fps from code poses. Carry/use/suit/seated hands use analytic two-bone positioning; gait and jump use keyed rotations. Sampled all frames and corrected negative foot minima using vertical Hips translation only. Armature-object and horizontal Hips movement are absent. Jump ends with repeated takeoff-pose samples; the game must clamp playback at clip end.
7. Saved one new derivative .blend with muted NLA tracks for clean rest-pose editing; exported nine separately named NLA tracks to GLB. Imported that GLB into an empty factory scene at 30 fps, checking exact bones/mesh nodes/clip names. Importer-generated bone display geometry is excluded from character mesh inventory; raw GLB mesh-node names are checked separately.
8. Rendered eight representative poses Ã— front/side Ã— crew/suit using Workbench at 640Ã—800. Workbench does not validate Godot transparency or game rendering. No Godot process was run.

## Measured results
```json
{
  "body_source": {
    "file": "G:\\nasa app\\grand_colony\\work\\_downloads\\human_base_meshes\\extracted\\human-base-meshes-bundle-v1.4.1\\human_base_meshes_bundle.blend",
    "object": "GEO-body_male_realistic",
    "triangles": 21160,
    "scale": 1.0651133223362708,
    "bounds": [
      [
        -0.4404309391975403,
        0.4402700662612915
      ],
      [
        -0.17945513129234314,
        0.11099401116371155
      ],
      [
        -0.005547828506678343,
        1.684413194656372
      ]
    ]
  },
  "body_reduction": {
    "before": 21160,
    "after": 15480
  },
  "body_triangles": 14089,
  "automatic_weights": {
    "operator": "ARMATURE_AUTO",
    "unweighted_vertices": 0
  },
  "suit_source": {
    "file": "G:\\nasa app\\grand_colony\\grand_colony.blend",
    "object": "qt_spacesuit",
    "triangles": 86524,
    "bounds": [
      [
        -0.3606029450893402,
        0.3606029450893402
      ],
      [
        -0.4448176920413971,
        0.07499999552965164
      ],
      [
        0.0,
        1.8808631896972656
      ]
    ],
    "loose_parts": 73
  },
  "suit_triangles": 42314,
  "suit_scale": {
    "radial": 1.4,
    "method": "piecewise joint-to-joint mapping; longitudinal scale is target/source segment length",
    "segments": {
      "Chest": 1.045454501308179,
      "Head": 1.0499997559691854,
      "UpperArmL": 1.0425351130132507,
      "LowerArmL": 0.7197853574593369,
      "HandL": 0.9048675318741186,
      "UpperArmR": 1.0425351130132507,
      "LowerArmR": 0.7197853574593369,
      "HandR": 0.9048675318741186,
      "UpperLegL": 1.1230149282194306,
      "UpperLegR": 1.1230149282194306,
      "FootL": 1.0499999224816323,
      "FootR": 1.0499999224816323,
      "LowerLegL": 1.2077964594468762,
      "LowerLegR": 1.2077964594468762
    }
  },
  "outer_shell_containment": {
    "method": "Union of ray-parity tests per connected suit component, temporary hole caps at joint cuts, 1 mm surface tolerance; includes coverall detail vertices",
    "regions": {
      "Torso": {
        "vertices": 1345,
        "outside": 10,
        "outside_percent": 0.743,
        "outside_bounds": [
          [
            -0.014021242968738079,
            0.013968748040497303
          ],
          [
            -0.08899086713790894,
            -0.08575351536273956
          ],
          [
            1.5349714756011963,
            1.534999966621399
          ]
        ],
        "outside_nearest_bones": {
          "Neck": 10
        }
      },
      "Arms": {
        "vertices": 2128,
        "outside": 1,
        "outside_percent": 0.047,
        "outside_bounds": [
          [
            -0.30321335792541504,
            -0.30321335792541504
          ],
          [
            -0.03324213996529579,
            -0.03324213996529579
          ],
          [
            1.061907172203064,
            1.061907172203064
          ]
        ],
        "outside_nearest_bones": {
          "LowerArmR": 1
        }
      },
      "Legs": {
        "vertices": 1218,
        "outside": 164,
        "outside_percent": 13.465,
        "outside_bounds": [
          [
            -0.2865745723247528,
            0.2865745723247528
          ],
          [
            -0.1850000023841858,
            0.12036692351102829
          ],
          [
            0.0,
            0.842154860496521
          ]
        ],
        "outside_nearest_bones": {
          "LowerLegR": 18,
          "UpperLegR": 11,
          "LowerLegL": 17,
          "UpperLegL": 10,
          "Hips": 1,
          "ToesL": 35,
          "FootL": 18,
          "ToesR": 35,
          "FootR": 19
        }
      }
    }
  },
  "rest_containment": {
    "method": "Union of ray-parity tests per connected suit component, temporary hole caps at joint cuts, 1 mm surface tolerance; includes coverall detail vertices",
    "regions": {
      "Torso": {
        "vertices": 1345,
        "outside": 0,
        "outside_percent": 0.0,
        "outside_bounds": [],
        "outside_nearest_bones": {}
      },
      "Arms": {
        "vertices": 2128,
        "outside": 0,
        "outside_percent": 0.0,
        "outside_bounds": [],
        "outside_nearest_bones": {}
      },
      "Legs": {
        "vertices": 1218,
        "outside": 0,
        "outside_percent": 0.0,
        "outside_bounds": [],
        "outside_nearest_bones": {}
      }
    }
  },
  "pressure_liners": [
    {
      "bone": "Chest",
      "triangles": 436,
      "source_body_vertices": 414,
      "clearance_m": 0.008
    },
    {
      "bone": "Neck",
      "triangles": 302,
      "source_body_vertices": 509,
      "clearance_m": 0.008
    },
    {
      "bone": "Spine",
      "triangles": 266,
      "source_body_vertices": 236,
      "clearance_m": 0.008
    },
    {
      "bone": "Hips",
      "triangles": 366,
      "source_body_vertices": 186,
      "clearance_m": 0.008
    },
    {
      "bone": "LowerArmR",
      "triangles": 450,
      "source_body_vertices": 237,
      "clearance_m": 0.008
    },
    {
      "bone": "UpperArmR",
      "triangles": 332,
      "source_body_vertices": 206,
      "clearance_m": 0.008
    },
    {
      "bone": "HandR",
      "triangles": 276,
      "source_body_vertices": 613,
      "clearance_m": 0.008
    },
    {
      "bone": "LowerArmL",
      "triangles": 440,
      "source_body_vertices": 234,
      "clearance_m": 0.008
    },
    {
      "bone": "UpperArmL",
      "triangles": 320,
      "source_body_vertices": 217,
      "clearance_m": 0.008
    },
    {
      "bone": "HandL",
      "triangles": 282,
      "source_body_vertices": 621,
      "clearance_m": 0.008
    },
    {
      "bone": "LowerLegR",
      "triangles": 202,
      "source_body_vertices": 268,
      "clearance_m": 0.008
    },
    {
      "bone": "UpperLegR",
      "triangles": 268,
      "source_body_vertices": 205,
      "clearance_m": 0.008
    },
    {
      "bone": "LowerLegL",
      "triangles": 200,
      "source_body_vertices": 269,
      "clearance_m": 0.008
    },
    {
      "bone": "UpperLegL",
      "triangles": 268,
      "source_body_vertices": 212,
      "clearance_m": 0.008
    },
    {
      "bone": "FootL",
      "triangles": 360,
      "source_body_vertices": 132,
      "clearance_m": 0.008
    },
    {
      "bone": "FootR",
      "triangles": 360,
      "source_body_vertices": 132,
      "clearance_m": 0.008
    }
  ],
  "mesh_weight_checks": {
    "Body_Head": {
      "unweighted": 0,
      "max_influences": 5,
      "max_sum_error": 0.06059853732585907
    },
    "Body_Arms": {
      "unweighted": 0,
      "max_influences": 4,
      "max_sum_error": 0.070645771920681
    },
    "Body_Legs": {
      "unweighted": 0,
      "max_influences": 4,
      "max_sum_error": 0.051002342253923416
    },
    "Body_Torso": {
      "unweighted": 0,
      "max_influences": 7,
      "max_sum_error": 0.111271221190691
    },
    "Suit_Helmet": {
      "unweighted": 0,
      "max_influences": 1,
      "max_sum_error": 0.0
    },
    "Suit_Torso": {
      "unweighted": 0,
      "max_influences": 1,
      "max_sum_error": 0.0
    },
    "Suit_Arms": {
      "unweighted": 0,
      "max_influences": 1,
      "max_sum_error": 0.0
    },
    "Suit_Legs": {
      "unweighted": 0,
      "max_influences": 1,
      "max_sum_error": 0.0
    }
  },
  "clips": {
    "idle": {
      "frames": 120,
      "seconds": 4.0,
      "minimum_foot_vertex_z": 0.00010000876500271261,
      "max_vertical_ground_correction": 7.827648751401739e-09
    },
    "walk": {
      "frames": 30,
      "seconds": 1.0,
      "minimum_foot_vertex_z": 9.991228580474854e-05,
      "max_vertical_ground_correction": 0.02089006081223488
    },
    "sprint": {
      "frames": 21,
      "seconds": 0.7,
      "minimum_foot_vertex_z": 9.993836283683777e-05,
      "max_vertical_ground_correction": 0.020815081894397736
    },
    "jump": {
      "frames": 12,
      "seconds": 0.4,
      "minimum_foot_vertex_z": 9.996719018090516e-05,
      "max_vertical_ground_correction": 0.00847566407173872
    },
    "land": {
      "frames": 12,
      "seconds": 0.4,
      "minimum_foot_vertex_z": 9.999076428357512e-05,
      "max_vertical_ground_correction": 0.008688006550073624
    },
    "carry": {
      "frames": 60,
      "seconds": 2.0,
      "minimum_foot_vertex_z": 0.00010000876500271261,
      "max_vertical_ground_correction": 7.827648751401739e-09
    },
    "use": {
      "frames": 30,
      "seconds": 1.0,
      "minimum_foot_vertex_z": 0.00010000876500271261,
      "max_vertical_ground_correction": 7.827648751401739e-09
    },
    "suit": {
      "frames": 30,
      "seconds": 1.0,
      "minimum_foot_vertex_z": 0.00010000876500271261,
      "max_vertical_ground_correction": 7.827648751401739e-09
    },
    "seated": {
      "frames": 1,
      "seconds": 0.03333333333333333,
      "minimum_foot_vertex_z": 0.010000566951930523,
      "max_vertical_ground_correction": 0
    }
  },
  "glb_animations": [
    {
      "name": "idle",
      "seconds": 4
    },
    {
      "name": "walk",
      "seconds": 1
    },
    {
      "name": "sprint",
      "seconds": 0.7
    },
    {
      "name": "jump",
      "seconds": 0.4
    },
    {
      "name": "land",
      "seconds": 0.4
    },
    {
      "name": "carry",
      "seconds": 2
    },
    {
      "name": "use",
      "seconds": 1
    },
    {
      "name": "suit",
      "seconds": 1
    },
    {
      "name": "seated",
      "seconds": 0.03333333333333333
    }
  ],
  "reimport": {
    "note": "Importer-generated bone display helpers are excluded from character mesh inventory; GLB nodes inspected separately.",
    "armatures": [
      {
        "name": "Armature",
        "bones": [
          "Hips",
          "Spine",
          "Chest",
          "Neck",
          "Head",
          "ShoulderL",
          "UpperArmL",
          "LowerArmL",
          "HandL",
          "HandAnchorL",
          "ShoulderR",
          "UpperArmR",
          "LowerArmR",
          "HandR",
          "HandAnchorR",
          "UpperLegL",
          "LowerLegL",
          "FootL",
          "ToesL",
          "UpperLegR",
          "LowerLegR",
          "FootR",
          "ToesR"
        ]
      }
    ],
    "meshes": [
      {
        "name": "Body_Arms",
        "triangles": 4150,
        "materials": [
          "Mat_Coverall",
          "Mat_Skin",
          "Mat_Ident"
        ],
        "armature_modifiers": 1
      },
      {
        "name": "Body_Head",
        "triangles": 5124,
        "materials": [
          "Mat_Skin",
          "Mat_Hair"
        ],
        "armature_modifiers": 1
      },
      {
        "name": "Body_Legs",
        "triangles": 2353,
        "materials": [
          "Mat_Coverall",
          "Mat_Boot"
        ],
        "armature_modifiers": 1
      },
      {
        "name": "Body_Torso",
        "triangles": 2462,
        "materials": [
          "Mat_Coverall",
          "Mat_Ident"
        ],
        "armature_modifiers": 1
      },
      {
        "name": "Suit_Arms",
        "triangles": 13452,
        "materials": [
          "Mat_Suit_kit_sign",
          "Mat_Suit_pp_suit",
          "Mat_Suit_pp_bearing",
          "Mat_Suit_kit_acc_hgr",
          "Mat_Suit_fabric_bl",
          "Mat_Suit_cream",
          "Mat_Suit_Liner"
        ],
        "armature_modifiers": 1
      },
      {
        "name": "Suit_Helmet",
        "triangles": 5694,
        "materials": [
          "Mat_Suit_pp_bearing",
          "Mat_Suit_kit_acc_hgr",
          "Mat_Suit_white",
          "Mat_Suit_black",
          "Mat_Suit_gunmetal",
          "Mat_Visor"
        ],
        "armature_modifiers": 1
      },
      {
        "name": "Suit_Legs",
        "triangles": 17490,
        "materials": [
          "Mat_Suit_kit_rubber",
          "Mat_Suit_pp_suit",
          "Mat_Suit_pp_bearing",
          "Mat_Suit_pp_boot",
          "Mat_Suit_Liner"
        ],
        "armature_modifiers": 1
      },
      {
        "name": "Suit_Torso",
        "triangles": 5677,
        "materials": [
          "Mat_Suit_kit_rubber",
          "Mat_Suit_kit_frame",
          "Mat_Suit_pp_suit",
          "Mat_Suit_pp_bearing",
          "Mat_Suit_kit_acc_hgr",
          "Mat_Suit_white",
          "Mat_Suit_black",
          "Mat_Suit_scr_green",
          "Mat_Suit_gunmetal",
          "Mat_Suit_red",
          "Mat_Suit_Liner"
        ],
        "armature_modifiers": 1
      }
    ],
    "materials": [
      "Mat_Boot",
      "Mat_Coverall",
      "Mat_Hair",
      "Mat_Ident",
      "Mat_Skin",
      "Mat_Suit_Liner",
      "Mat_Suit_black",
      "Mat_Suit_cream",
      "Mat_Suit_fabric_bl",
      "Mat_Suit_gunmetal",
      "Mat_Suit_kit_acc_hgr",
      "Mat_Suit_kit_frame",
      "Mat_Suit_kit_rubber",
      "Mat_Suit_kit_sign",
      "Mat_Suit_pp_bearing",
      "Mat_Suit_pp_boot",
      "Mat_Suit_pp_suit",
      "Mat_Suit_red",
      "Mat_Suit_scr_green",
      "Mat_Suit_white",
      "Mat_Visor"
    ],
    "actions": [
      {
        "name": "carry",
        "frame_range": [
          0.0,
          60.0
        ]
      },
      {
        "name": "idle",
        "frame_range": [
          0.0,
          120.0
        ]
      },
      {
        "name": "jump",
        "frame_range": [
          0.0,
          12.0
        ]
      },
      {
        "name": "land",
        "frame_range": [
          0.0,
          12.0
        ]
      },
      {
        "name": "seated",
        "frame_range": [
          0.0,
          1.0
        ]
      },
      {
        "name": "sprint",
        "frame_range": [
          0.0,
          21.0
        ]
      },
      {
        "name": "suit",
        "frame_range": [
          0.0,
          30.0
        ]
      },
      {
        "name": "use",
        "frame_range": [
          0.0,
          30.0
        ]
      },
      {
        "name": "walk",
        "frame_range": [
          0.0,
          30.0
        ]
      }
    ]
  },
  "checks": {
    "bone_names": true,
    "mesh_names": true,
    "animation_names": true,
    "no_image_textures": true,
    "body_budget": true,
    "suit_budget": true,
    "ground_all_sampled_frames": true,
    "root_horizontal_motion": "Hips keyed only vertically; armature object never animated",
    "source_hashes_unchanged": true
  },
  "source_sha256_before": {
    "G:\\nasa app\\grand_colony\\work\\_downloads\\human_base_meshes\\extracted\\human-base-meshes-bundle-v1.4.1\\human_base_meshes_bundle.blend": "3c121505651140ceb4d69fd1d8923f7788ffadd81672f5be14845a5f2c75c137",
    "G:\\nasa app\\grand_colony\\grand_colony.blend": "6aad006f0ca604ddf263e644d046f19e53f9b093082ebc3ebfb90d0cd15c916b"
  },
  "source_sha256_after": {
    "G:\\nasa app\\grand_colony\\work\\_downloads\\human_base_meshes\\extracted\\human-base-meshes-bundle-v1.4.1\\human_base_meshes_bundle.blend": "3c121505651140ceb4d69fd1d8923f7788ffadd81672f5be14845a5f2c75c137",
    "G:\\nasa app\\grand_colony\\grand_colony.blend": "6aad006f0ca604ddf263e644d046f19e53f9b093082ebc3ebfb90d0cd15c916b"
  }
}
```

Bone names: Hips, Spine, Chest, Neck, Head, ShoulderL, UpperArmL, LowerArmL, HandL, UpperLegL, LowerLegL, FootL, ToesL, HandAnchorL, ShoulderR, UpperArmR, LowerArmR, HandR, UpperLegR, LowerLegR, FootR, ToesR, HandAnchorR

## Checks and limitations
Script checks: source hashes, geometry budgets, body-weight coverage, rigid suit weights, per-frame foot minimum, exact raw-GLB mesh/clip names, imported bones/meshes/materials, no image textures. Rest containment uses per-connected-component ray parity with 1 mm tolerance and temporary caps on open shell cuts. Both outer-shell-only and complete-suit results are reported. This does not prove fit or absence of collisions throughout animation.
Visual review: Reviewed all 32 final01 Workbench stills through four front/side crew/suit contact sheets, plus the full-size jump side image. Also inspected six images rendered after importing the actual GLB: carry, sprint and seated, side view, both crew and suit. No exploded weights, detached suit pieces or obvious limb-through-torso penetration was observed at these sampled poses. This is not an exhaustive animation collision test.
The seated pose is authored for an approximately 0.45 m seat; there is no exported chair. Hold and loop flags are game playback settings, not glTF semantics.

## Known defects
- Suit components are rigid. Supplemental pressure liners and joint covers overlap the outer-shell cuts; joint creases remain stylized.
- Workbench evidence does not validate transparent-visor appearance in Godot.
- No exhaustive self-collision proof; see visual review notes.

## Final visual review and accepted limitations

Reviewed all 32 final01 Workbench stills through four front/side crew/suit contact sheets, plus the full-size jump side image. Also inspected six images rendered after importing the actual GLB: carry, sprint and seated, side view, both crew and suit. No exploded weights, detached suit pieces or obvious limb-through-torso penetration was observed at these sampled poses. This is not an exhaustive animation collision test.

- Rigid suit joints and convex mitten gloves are visibly stylized; pressure liners show through outer-shell gaps at hips, knees and ankles.
- The coverall, shoulder patch and hair cap retain hard shading or polygon seams; the boots are deliberately simple rounded forms.
- The original outer suit shell alone does not enclose all body vertices: torso 0.743%, arms 0.047%, legs 13.465% outside. Exported pressure liners bring the complete-suit measurements to 0% in all three regions.
- Seated feet are approximately 10 mm above ground. The pose targets an approximately 0.45 m seat; exact seat contact was not numerically certified.
- Only representative stills were visually inspected. Full-motion self-collision and Godot rendering, transparency and gameplay were not tested; Godot was not run.
- The body bundle README states CC0, while its separate embedded License names the Rain Rig under CC BY 4.0. Both exact texts are recorded; the colony suit licence was not established.
