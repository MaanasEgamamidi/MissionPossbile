from pathlib import Path
import json
import math
import re
from PIL import Image, ImageDraw, ImageFont, ImageOps

HERE = Path(__file__).resolve().parent
FONT = Path('C:/Windows/Fonts')
def font(size, bold=False):
    return ImageFont.truetype(str(FONT / ('segoeuib.ttf' if bold else 'segoeui.ttf')), size)

MENU_LABELS = ['Main menu / first launch', 'Main menu / saved colony', 'Play with friends / host', 'Play with friends / join', 'Pause menu', 'Settings / display', 'Settings / controls', 'Settings / graphics', 'Settings / audio', 'Voice & microphone', 'Crew selection', 'Crew / details', 'Crew / away from hub', 'Credits']
STATION_LABELS = {'power':'Power panel', 'lifesupport':'Life support', 'computer':'Colony computer', 'comms':'Comms console', 'heal':'Med station', 'food':'Greenhouse console', 'suits':'Suit rack', 'solar':'Sun tracker', 'bed':'Hydroponics unit', 'gym':'Gym', 'weather':'Weather station', 'workbench':'Workbench', 'maintenance':'Repair maintenance', 'cargo':'Cargo / inventory', 'cargo_empty':'Cargo / empty', 'cassette':'Cassette player', 'cassette_tape':'Cassette / selected tape', 'garage':'Garage', 'lab':'Lab', 'salvage':'Salvage', 'sample_site':'Sample site', 'scout_bay':'Scout bay', 'drone_pad':'Drone pad', 'rover_charger':'Rover charger', 'ore_deposit':'Ore deposit', 'record':'Record station', 'upgrade_console':'Upgrade console', 'board':'Transceiver board', 'survivor':'Patient', 'lab_sample':'Lab / sample analysis', 'weather_warn':'Weather / storm warning', 'power_help':'Power / help', 'lifesupport_help':'Life support / help', 'suits_help':'Suit rack / help', 'bed_help':'Hydroponics / help'}
INFO_LABELS = {'10_upgrades_locked':'Upgrade cards / locked', '11_upgrades_ready_at_computer':'Upgrades / ready at computer', '12_upgrades_ready_and_done':'Upgrades / installed & ready', '13_upgrades_more':'Upgrades / more details', '14_upgrades_help':'Upgrades / help', '20_summary_ok':'Colony summary', '21_summary_low':'Colony summary / low supplies', '22_summary_details':'Colony summary / details', '30_quiz':'Knowledge quiz', '31_quiz_wrong':'Quiz / incorrect answer', '32_quiz_right':'Quiz / correct answer', '33_quiz_away':'Quiz / away from station', '40_journal':'Colony journal'}
EXTRA_LABELS = {'01_blueprint':'Blueprint map', '02_sources':'Source register', '03_vitals_science':'Science behind the numbers', '04_power_life':'Power & life support drawer', '05_power_life_numbers':'Power & life support / numbers', '06_solar_build':'Solar field / build', '07_goals':'Goals & colony map', '09_colony_over':'Colony over'}
PUZZLE_LABELS = {'T01':'Lock the Relay', 'T02':'Patch the Relay', 'T03':'Sync the Turbine', 'T04':'Light the Power Bench', 'T06':'Water the Kale', 'T08':'Glaze the Dome', 'T09':'Sort the Lab Samples', 'T10':'Revive the Med Bay', 'T11':'Clear the Landing Lines', 'T12':'Seal the Airlock'}

groups = []
menus = sorted((HERE/'menus').glob('*.png'))
assert len(menus) == 14, f'Expected 14 menu shots, found {len(menus)}'
groups.append(('01', 'MENUS & SETTINGS', [(p, MENU_LABELS[i]) for i,p in enumerate(menus)]))
extras=[]
for p in sorted((HERE/'extra').glob('*.png')):
    key=p.stem
    label = EXTRA_LABELS.get(key, key.replace('08_section_', '').capitalize() + ' / section upgrades')
    extras.append((p,label))
assert len(extras)==13, f'Expected 13 extra screens, found {len(extras)}'
groups.append(('02', 'COLONY TOOLS & UPGRADE SECTIONS', extras))
info=[]
for p in sorted((HERE/'info').glob('*.png')):
    key=re.sub(r'^1920x1080_', '', p.stem)
    info.append((p,INFO_LABELS[key]))
assert len(info)==13, f'Expected 13 information panels, found {len(info)}'
groups.append(('03', 'PROGRESSION, KNOWLEDGE & JOURNAL', info))
stations=[]
for key,label in STATION_LABELS.items():
    p=HERE/'stations'/f'{key}_1080.png'
    assert p.exists(), p
    stations.append((p,label))
groups.append(('04', 'STATION MENUS & INVENTORY', stations))
puzzles=[]
for key,label in PUZZLE_LABELS.items():
    p=HERE/'puzzles'/f'{key}_start.png'
    assert p.exists(),p
    puzzles.append((p,f'{key} / {label}'))
locked=HERE/'puzzles'/'T02_wrong_specialist.png'
assert locked.exists()
puzzles.append((locked,'T02 / wrong specialist'))
groups.append(('05', 'REPAIR MINI-GAMES', puzzles))

COLS=5
TW,TH=1000,562
PAD,GAP=64,28
LABEL_H=66
CELL_H=TH+LABEL_H
SECTION_H=104
HEADER_H=260
FOOTER_H=100
W=PAD*2+COLS*TW+(COLS-1)*GAP
H=HEADER_H+sum(SECTION_H+math.ceil(len(items)/COLS)*(CELL_H+GAP)+38 for _,_,items in groups)+FOOTER_H
sheet=Image.new('RGB',(W,H),'#0b111a')
draw=ImageDraw.Draw(sheet)
draw.rectangle((0,0,W,12),fill='#f28a39')
draw.text((PAD,48),'MARS COLONY',font=font(74,True),fill='#f4f6fa')
draw.text((PAD,148),'COMPLETE MENU & INTERFACE SHEET',font=font(34),fill='#b6c3d4')
total=sum(len(x[2]) for x in groups)
draw.text((W-PAD,78),f'{total:02d} SCREENS',font=font(38,True),fill='#f28a39',anchor='ra')
draw.text((W-PAD,136),'Current game UI  /  15 NOV 2026',font=font(25),fill='#8395ad',anchor='ra')
draw.line((PAD,226,W-PAD,226),fill='#263243',width=2)
manifest=[]
y=HEADER_H
index=1
for number,title,items in groups:
    draw.rounded_rectangle((PAD,y+10,PAD+68,y+62),radius=12,fill='#f28a39')
    draw.text((PAD+34,y+33),number,font=font(26,True),fill='#111722',anchor='mm')
    draw.text((PAD+92,y+14),title,font=font(33,True),fill='#e6edf6')
    draw.text((W-PAD,y+20),f'{len(items)} captures',font=font(25),fill='#8395ad',anchor='ra')
    y+=SECTION_H
    for i,(path,label) in enumerate(items):
        cx=PAD+(i%COLS)*(TW+GAP)
        cy=y+(i//COLS)*(CELL_H+GAP)
        with Image.open(path) as original:
            pic=ImageOps.pad(original.convert('RGB'),(TW,TH),Image.Resampling.LANCZOS,color='#0b111a')
        sheet.paste(pic,(cx,cy))
        draw.rectangle((cx,cy,cx+TW-1,cy+TH-1),outline='#344357',width=2)
        draw.rectangle((cx,cy+TH,cx+TW-1,cy+CELL_H),fill='#172130')
        draw.text((cx+18,cy+TH+17),f'{index:02d}',font=font(23,True),fill='#f28a39')
        draw.text((cx+72,cy+TH+15),label,font=font(26,True),fill='#e6edf6')
        manifest.append({'number':index,'section':title,'title':label,'screenshot':str(path.relative_to(HERE))})
        index+=1
    y+=math.ceil(len(items)/COLS)*(CELL_H+GAP)+38
draw.line((PAD,H-90,W-PAD,H-90),fill='#263243',width=2)
draw.text((PAD,H-64),'Rendered directly from the current Godot project. Menus, tabs, station panels and representative UI states.',font=font(23),fill='#8395ad')
sheet.save(HERE/'mars_colony_menu_sheet.png',optimize=True)
preview=ImageOps.contain(sheet,(1800,18000),Image.Resampling.LANCZOS)
preview.save(HERE/'mars_colony_menu_sheet_preview.jpg',quality=90,optimize=True)
(HERE/'screenshots.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps({'screens':total,'size':[W,H],'png':str(HERE/'mars_colony_menu_sheet.png'),'preview':str(HERE/'mars_colony_menu_sheet_preview.jpg')}))
