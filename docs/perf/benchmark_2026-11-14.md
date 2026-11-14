# Perf overhaul A/B benchmark, 2026-11-14 13:19-13:32

RTX 4060 Ti 8 GB, i7-12700KF, Godot 4.7.2 Forward+, 1920x1080 window, High, vsync off, debug run, fresh colony each run.
Stale game window (PID 14308) closed first; GPU 6-31 % busy before each run (editor + Blender open, idle).
Runs: 1 off, 2 default, 3 all (except warm-up), 4 off, 5 default, 6 all. 'off spread' = drift between the two baseline runs: a change smaller than it is noise.
Raw JSON: docs/perf/results/ab_*.json. Made with tools/perf/run_perf_ab.sh + tools/perf/summarise_ab.py.

### GPU ms (mean)

| View | 1 off | 2 default | 3 all | 4 off | 5 default | 6 all | off spread | default vs off | all vs off |
|---|---|---|---|---|---|---|---|---|---|
| room_command_room | 16.3 | 15.6 | 16.4 | 17.2 | 16.4 | 16.8 | +5 % | -4 % | -1 % |
| room_power_room | 19.6 | 19.1 | 20.6 | 20.9 | 20.7 | 20.5 | +6 % | -2 % | +2 % |
| room_greenhouse | 31.7 | 31.1 | 35.1 | 35.4 | 34.6 | 34.9 | +12 % | -2 % | +4 % |
| room_med_bay | 18.0 | 15.9 | 17.0 | 19.1 | 17.1 | 17.0 | +6 % | -11 % | -8 % |
| room_life_support | 17.9 | 16.1 | 15.9 | 18.8 | 15.9 | 16.0 | +5 % | -13 % | -13 % |
| plaza_through_glass | 19.3 | 20.4 | 20.3 | 20.4 | 20.5 | 20.3 | +6 % | +3 % | +3 % |
| exterior_garage | 16.3 | 16.4 | 16.2 | 16.8 | 16.2 | 16.4 | +3 % | -2 % | -2 % |
| exterior_storm | 13.8 | 13.8 | 13.7 | 14.0 | 13.7 | 13.7 | +1 % | -1 % | -1 % |
| four_suited_crew | 17.6 | 17.4 | 17.3 | 18.2 | 17.4 | 17.5 | +3 % | -3 % | -3 % |
| rover_route | 16.5 | 17.4 | 17.3 | 17.6 | 17.4 | 17.4 | +6 % | +2 % | +2 % |

### Frame ms (p50)

| View | 1 off | 2 default | 3 all | 4 off | 5 default | 6 all | off spread | default vs off | all vs off |
|---|---|---|---|---|---|---|---|---|---|
| room_command_room | 16.1 | 15.7 | 16.5 | 17.2 | 16.3 | 16.8 | +7 % | -4 % | -0 % |
| room_power_room | 20.8 | 20.4 | 21.3 | 21.7 | 22.0 | 21.5 | +4 % | -0 % | +1 % |
| room_greenhouse | 32.0 | 31.0 | 36.3 | 36.7 | 35.5 | 35.9 | +15 % | -3 % | +5 % |
| room_med_bay | 18.9 | 16.9 | 17.9 | 20.1 | 18.0 | 17.9 | +7 % | -11 % | -8 % |
| room_life_support | 18.2 | 16.7 | 16.4 | 18.6 | 16.4 | 16.5 | +2 % | -10 % | -11 % |
| plaza_through_glass | 19.7 | 21.1 | 21.0 | 20.8 | 21.2 | 20.8 | +6 % | +4 % | +3 % |
| exterior_garage | 14.9 | 15.6 | 15.0 | 15.4 | 15.0 | 15.5 | +3 % | +1 % | +1 % |
| exterior_storm | 13.5 | 13.8 | 13.5 | 13.5 | 13.7 | 13.6 | +0 % | +2 % | +0 % |
| four_suited_crew | 16.7 | 18.0 | 17.0 | 17.3 | 17.1 | 18.1 | +3 % | +3 % | +3 % |
| rover_route | 16.9 | 17.8 | 17.9 | 18.0 | 17.9 | 18.0 | +6 % | +2 % | +3 % |

### Draw calls (mean)

| View | 1 off | 2 default | 3 all | 4 off | 5 default | 6 all | off spread | default vs off | all vs off |
|---|---|---|---|---|---|---|---|---|---|
| room_command_room | 8326 | 8009 | 7922 | 7968 | 7973 | 8090 | +4 % | -2 % | -2 % |
| room_power_room | 3549 | 3505 | 3508 | 3534 | 3499 | 3510 | +0 % | -1 % | -1 % |
| room_greenhouse | 11270 | 11071 | 11064 | 11287 | 10997 | 11020 | +0 % | -2 % | -2 % |
| room_med_bay | 10758 | 11281 | 11243 | 10792 | 11280 | 11223 | +0 % | +5 % | +4 % |
| room_life_support | 10770 | 9273 | 9257 | 10655 | 9099 | 9134 | +1 % | -14 % | -14 % |
| plaza_through_glass | 13484 | 14817 | 14568 | 13453 | 14419 | 14434 | +0 % | +9 % | +8 % |
| exterior_garage | 7106 | 5049 | 5077 | 7005 | 5055 | 5062 | +1 % | -28 % | -28 % |
| exterior_storm | 2794 | 1969 | 1978 | 2767 | 1980 | 1999 | +1 % | -29 % | -28 % |
| four_suited_crew | 8079 | 5979 | 5958 | 7927 | 6034 | 6035 | +2 % | -25 % | -25 % |
| rover_route | 1450 | 1452 | 1450 | 1487 | 1493 | 1487 | +3 % | +0 % | -0 % |

### Primitives (mean)

| View | 1 off | 2 default | 3 all | 4 off | 5 default | 6 all | off spread | default vs off | all vs off |
|---|---|---|---|---|---|---|---|---|---|
| room_command_room | 13.53 M | 13.33 M | 13.26 M | 13.34 M | 13.24 M | 13.36 M | +1 % | -1 % | -1 % |
| room_power_room | 6.24 M | 6.23 M | 6.24 M | 6.17 M | 6.22 M | 6.24 M | +1 % | +0 % | +1 % |
| room_greenhouse | 13.37 M | 13.18 M | 13.17 M | 13.38 M | 13.14 M | 13.14 M | +0 % | -2 % | -2 % |
| room_med_bay | 11.85 M | 12.13 M | 12.11 M | 11.87 M | 12.12 M | 12.09 M | +0 % | +2 % | +2 % |
| room_life_support | 11.78 M | 11.31 M | 11.29 M | 11.72 M | 11.23 M | 11.26 M | +0 % | -4 % | -4 % |
| plaza_through_glass | 14.18 M | 14.49 M | 15.29 M | 14.17 M | 14.43 M | 14.41 M | +0 % | +2 % | +5 % |
| exterior_garage | 8.81 M | 8.33 M | 8.42 M | 8.73 M | 8.33 M | 8.35 M | +1 % | -5 % | -4 % |
| exterior_storm | 5.26 M | 5.10 M | 5.11 M | 5.24 M | 5.10 M | 5.12 M | +0 % | -3 % | -3 % |
| four_suited_crew | 9.55 M | 9.09 M | 9.07 M | 9.45 M | 9.12 M | 9.12 M | +1 % | -4 % | -4 % |
| rover_route | 5.42 M | 5.42 M | 5.42 M | 5.43 M | 5.43 M | 5.43 M | +0 % | +0 % | -0 % |

## Image comparison (one still per view, 45 frames after arriving)

`mean_abs` 0-255, `changed` = pixels off by more than 8/255, `ssim` 1.0 = identical. tools/perf/compare_shots.py.

### off vs default
```
exterior_garage        mean_abs   0.076  changed   0.03 %  ssim 0.9994
exterior_storm         mean_abs   0.105  changed   0.05 %  ssim 0.9994
four_suited_crew       mean_abs   0.741  changed   0.44 %  ssim 0.9963
plaza_through_glass    mean_abs   0.002  changed   0.00 %  ssim 1.0000
room_command_room      mean_abs   0.047  changed   0.01 %  ssim 0.9998
room_greenhouse        mean_abs   0.000  changed   0.00 %  ssim 1.0000
room_life_support      mean_abs   0.124  changed   0.07 %  ssim 0.9995
room_med_bay           mean_abs   1.789  changed   5.77 %  ssim 0.9564
room_power_room        mean_abs   0.000  changed   0.00 %  ssim 1.0000
rover_route            mean_abs   0.132  changed   0.41 %  ssim 0.9983
```

### off vs all
```
exterior_garage        mean_abs   0.016  changed   0.03 %  ssim 0.9998
exterior_storm         mean_abs   0.054  changed   0.03 %  ssim 0.9996
four_suited_crew       mean_abs   0.582  changed   0.86 %  ssim 0.9914
plaza_through_glass    mean_abs   0.008  changed   0.01 %  ssim 1.0000
room_command_room      mean_abs   0.117  changed   0.04 %  ssim 0.9997
room_greenhouse        mean_abs   0.005  changed   0.00 %  ssim 1.0000
room_life_support      mean_abs   0.117  changed   0.07 %  ssim 0.9996
room_med_bay           mean_abs   3.857  changed  12.54 %  ssim 0.9365
room_power_room        mean_abs   0.013  changed   0.01 %  ssim 0.9998
rover_route            mean_abs   0.000  changed   0.00 %  ssim 1.0000
```

The only visible difference (Med Bay 5.8 %, four suited crew 0.4 %) is the outline of the crew standing in front of the camera: their idle animation is at a slightly different pose. The rooms themselves are pixel-identical.

## The first run (13:03-13:16) was wrong and was thrown away

1. With the defaults, Med Bay and every outdoor view came out **dark**, and the frame times there looked 60-70 %
   faster. Cause: the camera's cull mask also culls lights, reflection probes and decals by their own `layers`, and
   those nodes sit on layer 1 by default, which is the Hangar bay's zone layer. Whenever the Hangar bay went to sleep,
   the sun and every lamp went with it. Fixed in `ZoneManager._pin()` (lights, probes, decals and non-map objects on
   layer 1 also get layer 20, which is never hidden); `tests/test_perf.gd` now checks it.
2. `--perf-on` also switched on the shader warm-up, whose black overlay and camera tour sat inside the "all" timings.
   The bench now runs "all" with the warm-up off.
