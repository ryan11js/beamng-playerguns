# Player Guns

Shoot where you look. Player Guns arms BeamNG's Walking Mode and any car with roof bars, in singleplayer and BeamMP. Built on [`player_weapon_2`](https://www.beamng.com/threads/player-weapons-2.94445/) by AwesomeCarl & AgentY.

## Features

- Seven weapons with their own meshes, stats, and sounds. Cycle with O and P.
- Camera aim: bullets follow your crosshair, on foot or while driving.
- Physics bullets that break beams on target vehicles. Tires pop, panels dent, suspensions buckle.
- Bazooka with a 4m blast radius and an outward force push.
- A "Player Guns" preset on 27 vanilla cars: spawn it and drive away armed.
- Visual rebinding for keyboard, mouse, and controller in the Controls app.
- BeamMP sync: remote clients see your aim and replay your shots.
- Snowman body for walking mode, or stay invisible.

### Weapon Roster

| # | Weapon | Fire Rate | Mag | Reload | Spread | Damage Notes |
|---|---|---|---|---|---|---|
| 1 | **Pistol** | ~333 rpm | 12 | 1.5s | low (1.5°) | Light sidearm. No muzzle smoke. |
| 2 | **Uzi** | 952 rpm | 32 | 1.8s | wide (7°) | Spray-and-pray SMG. |
| 3 | **Thompson** | 600 rpm | 50 | 3.2s | medium (4.5°) | Big drum mag, slower fire. |
| 4 | **AKM** | 420 rpm | 30 | 2.7s | controlled (3°) | Hits harder than the SMGs; bigger impact radius. |
| 5 | **Sniper** | ~43 rpm | 5 | 3.0s | pixel-perfect (0°) | High-mass round, 1m impact radius, breaks up to 25 beams. |
| 6 | **Minigun** | 1500 rpm | 250 | 4.5s | wide (5.5°) | Suppressive fire. |
| 7 | **Bazooka** | 60 rpm | 1 | 3.0s | tight (1°) | Explosive: 4m radius AoE, applies 80 kN outward force to nearby nodes. |

All ballistic rounds prioritize **pressure beams** (tire/airspring beams) on impact, so tires pop reliably with even small hit radii.

Default weapon order is Pistol → … → Bazooka. P cycles forward, O cycles back.

## Controls

Default keybinds:

| Action | Default |
|---|---|
| Fire | Left Mouse Button |
| Reload | Q |
| Previous Weapon | O |
| Next Weapon | P |
| Weapon Wheel | X (hold) |

**Weapon wheel:** add the **Player Guns Wheel** app (Ctrl+U, the box can sit anywhere). Hold X, flick the mouse toward a weapon, release. The wheel builds itself from the weapon list, so new weapons appear on it without UI changes.

**Recommended:** add the **Player Guns Controls** UI app (Ctrl+U) and rebind there. The app shows a clickable **keyboard layout, mouse buttons, and Xbox-style controller layout** (face buttons, D-pad, bumpers, triggers, stick clicks). Picks are saved as **native BeamNG bindings** (the same persistence as Options → Controls), so they work everywhere and survive Tab-switching.

You can also rebind in Options → Controls (search "PlayerGuns"). Global factory maps ship in `settings/inputmaps/*_playerGuns.json` inside the mod (not the old per-unicycle vehicle maps).

Avoid binding to keys with stock conflicts (R = Reset Vehicle, Tab = Switch Vehicle, E/Q sometimes overridden).

## Install

1. Grab `PlayerGuns-vX.Y.Z.zip` from the [Releases page](https://github.com/ryan11js/beamng-playerguns/releases) (or build your own with `git archive --format=zip HEAD`).
2. Drop the zip into your BeamNG mods folder:
   - `C:\Users\<USERNAME>\AppData\Local\BeamNG\BeamNG.drive\current\mods\repo`
3. Launch BeamNG. Enable PlayerGuns in the Mods menu if needed.
4. **Important: clear vehicle cache.** BeamNG caches jbeams and won't see new slots/parts until you do this. Either:
   - In-game: Main Menu → Repair → "Clear cache and reload" (Ctrl+R also reloads on some versions), **or**
   - Filesystem: delete `C:\Users\<USERNAME>\AppData\Local\BeamNG\BeamNG.drive\<version>\cache\` and restart the game.

## Use

1. Spawn any vehicle and enter a level.
2. Press `F` to exit the vehicle (Walking Mode — toggles you into the unicycle).
3. Open the Parts Manager (`Ctrl+W`) on the unicycle:
   - Find the **Visual Meshes** slot → set to **Player Guns - Armed Body (Invisible)** or **Player Guns - Armed Body (Snowman)**.
   - A new **Player Guns Weapon** sub-slot appears → leave default (**Player Guns - Weapon System**). The bullet pool is built in — there is no separate ammo part anymore.
4. Open the UI app menu (Ctrl+U) and add **Player Guns Crosshair** (center), **Player Guns Ammo** (bottom-right), and **Player Guns Controls** (top-left, for keybinds). Crosshair and Ammo share the same controller stream; Controls edits bindings that persist across Tab switches.
5. Aim with the mouse, fire with your bound key. Switch weapons with your bound keys.

> The "Invisible Body" name is honest: picking this variant hides the beamling/snowman/debug body and you'll only see the floating gun. This is the simplest pattern the BeamNG slot system allows (a body part *replaces* the body — it doesn't extend it). A future version can add a "PlayerGuns Armed (Beamling)" variant that keeps the default body mesh.

### Roof mount (drive-by shooting)

The fast way: open the vehicle selector, pick any of the 27 supported cars, and choose the **Player Guns** configuration. The car spawns with roof bars and the gun installed.

Supported vanilla cars: Autobello, Barstow, Bastion, Bluebuck, Burnside, BX, Covet, ETK 800, ETK C, ETK I, Fullsize, Hopper, Lansdale, LeGran, Midsize, MD-Series, Miramar, Moonhawk, Nine, Pessima, Pigeon, SBR, Scintilla, Sunburst, Van, Vivace, Wendover.

The manual way works on any car with roof bars, including mods:

1. In the Parts Manager, set the car's roof accessory slot to its **cargo load roof bars** part.
2. Set **Roof Load** to **Player Guns - Roof Mount**.
3. Drive. Same binds as on foot. Bullets follow your crosshair in first or third person, straight up included.

**Crosshair app:** Ctrl+U → add **Player Guns Crosshair** → drag/resize the app box to cover the **entire game view** (edge to edge). Aim works without the app (GE mouse poll), but the visible crosshair only renders inside the app’s rectangle. Remove any old tiny crosshair app first, then re-add after updating the mod.

Log markers for roof testing (paste `beamng.log` into `log.txt`, then grep):

- `playerGuns.mount` — confirms mount context `roof` and resolved muzzle node
- `playerGuns.tick` — includes `mount=roof`, `seated=true` while driving
- `playerGuns.inputBridge` — `ACTIVE` when the armed car is your player vehicle

## File Layout

```
PlayerGuns/
├── mod_info/info.json
├── scripts/playerGuns/modScript.lua               # loads GE extensions (input, aim, telemetry)
├── lua/ge/extensions/playerGuns/input.lua         # native-binding rebind backend + toggles
├── lua/ge/extensions/playerGuns/aim.lua           # camera ray / crosshair aim
├── lua/ge/extensions/playerGuns/telemetry.lua     # session recorder → settings/playerGuns/telemetry.json
├── lua/ge/extensions/core/input/actions/playerGuns.json
├── settings/inputmaps/                            # global factory binds (keyboard + mouse)
├── lua/vehicle/controller/playerGuns.lua          # controller entry (requires playerGuns/core)
├── lua/vehicle/playerGuns/                        # shared modules (weapons, bullets, damage, telem, core)
├── vehicles/common/playerGuns/
│   ├── playerGuns_roof.jbeam                      # roofbars_load mount for any car with roof bars
│   └── playerGuns_roof_weapon.jbeam               # roof weapon + built-in 100-node bullet pool
├── vehicles/<car>/                                # 27 vanilla cars
│   ├── Player Guns.pc                             # ready-to-spawn preset
│   ├── Player Guns.png                            # preset image
│   └── info_Player Guns.json
├── vehicles/unicycle/
│   ├── input_actions_playerGuns.json              # empty stub (global actions used instead)
│   ├── inputmaps/                                 # empty stubs (avoid duplicate vehicle maps)
│   ├── playerGuns_body.jbeam                      # body variant, fills stock unicycle_meshes slot; exposes weapon sub-slot
│   ├── playerGuns_main.jbeam                      # weapon system + built-in 100-node bullet pool
│   ├── playerGuns.materials.json                  # PBR materials
│   ├── playerGuns_models.dae                      # gun mesh (Uzi/Thompson/AKM/Sniper/Bazooka/etc)
│   └── textures/                                  # PBR textures
└── ui/modules/apps/
    ├── PlayerGunsCrosshair/                       # Angular HUD: center-screen crosshair
    ├── PlayerGunsAmmo/                            # Angular HUD: weapon name + ammo + reload bar
    ├── PlayerGunsControls/                        # Angular HUD: toggles + visual key/controller rebinding
    └── PlayerGunsDebug/                           # Angular HUD: live telemetry + JSON dump button
```

## Sounds

Weapons play .ogg files from `vehicles/common/playerGuns/sfx/` and fall back to the stock sample when a file is missing. See the table in [vehicles/common/playerGuns/sfx/README.md](vehicles/common/playerGuns/sfx/README.md) for the expected names and license-safe sources.

## Telemetry / Debugging

The mod records what actually happens to every bullet (intended aim vs real
velocity, impact distance from the firing car, gun-mount deformation) and
aggregates it per minute. To review a session:

1. Add the **Player Guns Debug** UI app (Ctrl+U) — live counters: shots,
   impacts, self-hits, trajectory error, mount sag.
2. Click **Dump JSON** (or run `extensions.playerGuns_telemetry.dump()` in the
   console) — writes `settings/playerGuns/telemetry.json` in the userfolder.
3. That one small file replaces grepping `beamng.log` for per-shot lines.

## How Multiplayer Works

The original `player_weapon_2` mod doesn't work in BeamMP because its camera direction is fetched locally from `core_camera.getForward()` (a game-engine call), and that state isn't synced. PlayerGuns fixes this by:

1. Writing the aim vector into `electrics.values.pg_aim_x/y/z` every frame. BeamMP syncs electrics, so remote clients see where the shooter is pointing.
2. Gating input handling (LMB / Q / O / P) to local-owned vehicles only (`v.mpVehicleType ~= "R"`), so remote clients don't double-fire.
3. Incrementing `electrics.values.pg_fire_pulse` on each shot. Remote clients detect pulse changes and locally replay `launchNextBullet()` using the synced aim direction — so the bullet node visibly flies on every client.
4. Particles and bullet-impact detection run on every client (purely visual).

## Credits

- **AwesomeCarl, AgentY** — original `player_weapon_2` mod. The bullet-node firing system, ammo jbeam pattern, camera-callback recipe, weapon stats, gun mesh, and PBR textures are all adapted from their work with permission per the bCDDL license model.
- **DaddelZeit, lucky4luuk** — helped AwesomeCarl get camera aim working originally.
- **stefan750** — UniversalWeapons mod served as the slot-injection reference.

## Status / TODOs

- [ ] BeamMP testing — roof + on-foot; validate `pg_fire_pulse` and `pg_aim_*` sync on armed cars in an actual MP session.
- [ ] Replace `CrashTestSound` per-weapon pitch hack with real OGG fire sounds in `vehicles/unicycle/sounds/`. Weapon table lives in [`lua/vehicle/playerGuns/weapons.lua`](lua/vehicle/playerGuns/weapons.lua).
- [ ] First-person gun visibility (inherited limitation from `player_weapon_2` — requires camera override, deliberately deferred to stay repo-friendly).
- [x] Roof mount (`playerGuns_roof`) — camera aim, full roster, no turret recoil.
