# Mars Colony — Player Guide

A cooperative game about keeping a small colony on Mars alive. You can play alone or with up to four people on the
same home or school network. This guide is for players aged about 9 to 12 and for the grown-ups helping them.

## 1. Install and start

1. You need a Windows 10 or Windows 11 computer (64-bit). There is no Mac or Linux version.
2. Unzip the whole `MarsColony_windows` folder somewhere you can find it, for example your Desktop.
   Keep every file in that folder together. The game needs `MarsColony.exe`, `MarsColony.pck` and the
   voice library file (`libtwovoip...dll`) to sit next to each other.
3. Double-click `MarsColony.exe`.
4. The game is not code-signed, so Windows may show a blue "Windows protected your PC" box the first time.
   If you got the folder from someone you trust, choose **More info**, then **Run anyway**.

You do **not** need the internet to play. You do not need an account.

## 2. The main menu

| Button | What it does |
| --- | --- |
| **Continue** | Carries on with your saved colony. |
| **New colony** | Starts a fresh colony. |
| **Host on this network** | Starts a colony that friends on the same network can join (see section 5). |
| **Join a colony** | Joins a friend's colony. You type the host's address and port. |
| **Settings** | Screen, graphics, text size, controls, camera and voice. |
| **Sources and credits** | Where the facts in the game come from, and who made the tools and models. |
| **Quit** | Saves and closes the game. |

## 3. Controls

These are the starting keys. You can change any of them in **Settings**.

| Key | What it does |
| --- | --- |
| W A S D | Walk forward, back, left, right. In the rover: drive and steer. |
| Mouse | Look around. |
| Shift | Sprint (hold it; Settings can make it a tap on/off). |
| Space | Jump. In the rover: brake. |
| E | Use things: stations, doors, buttons, pick up and put down items, get in and out of the rover. |
| G or left mouse button | Grab, drop or throw a held item. |
| Tab | Switch between first person (your own eyes) and third person (camera behind you). |
| M | Open the blueprint map. |
| I | Your cargo (what you carry). |
| C | The crew screen. |
| V | Push to talk (hold it while you speak). |
| P | Power and life support drawer. |
| B | Build drawer (at the solar field). |
| H | Fold or unfold the supplies bar. |
| J | Fold or unfold the goals card. |
| K | Close a Mission Control message. |
| F1 | The science behind the numbers. |
| N | Ask for a tutorial hint. |
| L | The colony journal (story log). |
| Esc | Close the open screen. If nothing is open: pause menu and settings. |
| Shift + Backspace | Open the source register (where every fact comes from). |

The game always starts in first person.

## 4. Your first steps

- A new colony starts with the **tutorial**. It has ten short stages: walk, put on your suit at the suit rack,
  go through the airlock, clean a solar panel, share out power, grow plants, look after your health, fix the radio,
  solve one problem on your own, and then explore.
- Stuck? Press **N** for a hint. Hints also appear by themselves if nothing has happened for a while.
- Press **L** to read the colony journal. It holds notes left by an earlier (made-up) crew. Reading them is optional.
- There are four crew members, each with a speciality: electrical and communications, medical and life support,
  biology and food, and field engineering and geology. Some jobs need a certain specialist. If nobody is playing the
  specialist you need, go to the **hub** and switch to that crew member there.
- Anyone can read gauges, carry supplies, clean solar panels, drive a finished rover and use ordinary chargers.
- Outside, keep an eye on your **suit charge**. If a crew member's condition reaches zero, they are rescued back
  to the hub. What they were carrying is left in a box where it happened, so you can go back for it.

## 5. Playing together on a network (LAN)

Up to **four** players: one host and up to three friends. Everyone must be on the **same local network**
(the same home or school Wi-Fi or wired network). There is no internet play.

**To host**

1. Choose **Host on this network**. The port is **24680** unless you change it.
2. Tick **Continue my saved colony** to play your saved game, or leave it off to start a new one.
   (Starting a new hosted colony replaces your saved one; the old save is kept as a backup.)
3. Choose **Start hosting**. The game shows your address, for example `192.168.1.20`, and the port.
   The pause menu (Esc) shows it again.

**To join**

1. Choose **Join a colony**.
2. Type the host's address and port, then choose **Join**.

**Windows Firewall:** the first time you host, Windows may ask whether to allow Mars Colony on the network.
Allow it on **private** networks. If it is refused, nobody else can join. A grown-up can change this later in
Windows Security, under Firewall and network protection.

Good to know:

- The host's computer keeps the colony and the save. If the host leaves, everyone else goes back to the menu,
  and the host can load the colony again later.
- If your own connection drops, your crew member goes safely back to the hub with everything they carried.
  You can join again.
- Each player controls one crew member. Two players cannot take the same one.
- In a shared game, the game only pauses when **every** player agrees. Opening your own screen does not pause the others.

## 6. Talking (voice)

- Hold **V** to talk. Let go when you finish.
- **Indoors**, people near you hear you. Voices fade with distance, and you are heard in the next room only
  through an open door.
- **Outside** (and in the rover outside the garage) you talk over the **radio**. The radio is broken at first.
  Each repair stage, installed at the comms console, makes radio messages arrive sooner:
  no radio yet → 30 seconds late → 15 seconds → 5 seconds → almost at once.
  The delay is the damaged radio's own fault in the story. It is not how long messages take to reach Earth.
- In **Settings** you can choose your microphone, mute it and set how loud voices are.
- Without a microphone you can still play and still hear the others.
- The game never records or saves voices.

## 7. Saving

- The game saves by itself about once a minute, and when you choose **Quit**. Only the host's computer saves.
- Saves are in:
  `%APPDATA%\Godot\app_userdata\Mars Colony\saves\`
  (paste that line into the File Explorer address bar). The main save is `colony.json`; the two newest backups are
  `colony.bak1.json` and `colony.bak2.json`. If the newest save is damaged, the game loads a backup and says so.
- Your settings (`settings.json`) and key changes (`input.json`) are one folder up, in `Mars Colony\`.
- Nothing gets worse while the game is closed. Mars waits for you.

## 8. Settings

- **Graphics:** Low, Medium, High or Ultra. Try Medium or Low if the game feels slow.
- **Screen and text:** size of menus, text size (normal, large, extra large), subtitles, high-contrast colours,
  reduce motion (no camera bob or fades).
- **Camera and controls:** field of view, mouse speed, invert mouse, hold or tap to sprint, and changing any key.
- **Voice:** microphone, mute, voice volume.
- **Sol length (host only, in the pause menu):** a sol is a Mars day. In the game it lasts 20 real minutes unless the
  host changes it (5 to 120 minutes). This only changes how fast the game clock runs; a real Mars day stays the same length.

## 9. Without the internet

- Everything you need is inside the game folder, including the Mars weather data.
- When the computer happens to be online, the game quietly checks about once an hour for newer weather data from the
  science archives. A new file is only used after it has been checked, and only from your next new game or load.
  If anything goes wrong, the game keeps the data it already has.

## 10. What is real and what is made up

- **Made up (fiction):** the year 2080 colony, the crew, the story notes, the broken radio, and the game's numbers for
  how fast things fill, drain or grow. The game simplifies many things so they are fun to play.
- **Real:** facts about Mars such as its gravity (3.73 m/s²), the weather and dust records (from NASA's Perseverance
  rover weather station at Jezero crater, and from published Mars dust maps), and how real life-support ideas work
  (such as recycling water on the International Space Station and the MOXIE oxygen experiment on Mars).
- Each fact in the game is labelled. Press **Shift + Backspace** (or open **Sources and credits**) to see where it
  comes from.
- This game is not made, approved or endorsed by NASA.
