# PlayerGuns

A BeamNG.drive mod that lets the player equip and shoot guns while in Walking Mode (i.e. outside a vehicle). **Architecture adapted from** [`player_weapon_2`](https://www.beamng.com/threads/player-weapons-2.94445/) by AwesomeCarl & AgentY, **with added BeamMP multiplayer support**.

## Features

- **Seven weapons**, switch on the fly with O/P. Each shows its own mesh and has its own stats.
- **Camera-based aim** with per-weapon recoil spread (Sniper pixel-perfect, AKM controlled, Uzi/Minigun spray).
- **Physics bullets** with damage that breaks beams on target vehicles — pops tires, dents panels, rocks suspension.
- **Bazooka does AoE damage** — 4m blast radius with fireball particles and an outward force-push.
- **Two HUD apps**: a centered Crosshair and a bottom-right Ammo box. Place each independently.
- **Snowman body** option (or stay invisible).
- **BeamMP-compatible**: aim syncs via `electrics`, fire-pulse counter replays shots on remote clients.

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

**Recommended:** add the **Player Guns Controls** UI app (Ctrl+U) and rebind there. Bindings are saved to `settings/playerGuns/keybinds.json` and applied every frame by the mod’s input bridge, so they **survive Tab-switching** between walking-mode snowmen.

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
   - Find the **Visual Meshes** slot → set to **PlayerGuns Armed (Invisible Body)** or **PlayerGuns Armed (Snowman)**.
   - A new **Weapon** sub-slot appears → leave default (**PlayerGuns Weapon System**).
   - A nested **Ammo** sub-slot appears → leave default (**100 Bullets**).
4. Open the UI app menu (Ctrl+U) and add **Player Guns Crosshair** (center), **Player Guns Ammo** (bottom-right), and **Player Guns Controls** (top-left, for keybinds). Crosshair and Ammo share the same controller stream; Controls edits bindings that persist across Tab switches.
5. Aim with the mouse, fire with your bound key. Switch weapons with your bound keys.

> The "Invisible Body" name is honest: picking this variant hides the beamling/snowman/debug body and you'll only see the floating gun. This is the simplest pattern the BeamNG slot system allows (a body part *replaces* the body — it doesn't extend it). A future version can add a "PlayerGuns Armed (Beamling)" variant that keeps the default body mesh.

## File Layout

```
PlayerGuns/
├── mod_info/info.json
├── scripts/playerGuns/modScript.lua               # loads GE input bridge extension
├── lua/ge/extensions/playerGuns/input.lua         # manual input poll + binding persistence
├── lua/ge/extensions/core/input/actions/playerGuns.json
├── settings/inputmaps/                            # global factory binds (keyboard + mouse)
├── lua/vehicle/controller/playerGuns.lua          # main controller (camera-aim + physics bullets + MP sync)
├── vehicles/unicycle/
│   ├── input_actions_playerGuns.json              # empty stub (global actions used instead)
│   ├── inputmaps/                                 # empty stubs (avoid duplicate vehicle maps)
│   ├── playerGuns_body.jbeam                      # body variant, fills stock unicycle_meshes slot; exposes weapon sub-slot
│   ├── playerGuns_main.jbeam                      # weapon system part, fills playerGuns_weapon sub-slot
│   ├── playerGuns_ammo.jbeam                      # 100 bullet nodes, fills playerGuns_ammo sub-slot
│   ├── playerGuns.materials.json                  # PBR materials
│   ├── playerGuns_models.dae                      # gun mesh (Uzi/Thompson/AKM/Sniper/Bazooka/etc)
│   └── textures/                                  # PBR textures
└── ui/modules/apps/
    ├── PlayerGunsCrosshair/                       # Angular HUD: center-screen crosshair
    ├── PlayerGunsAmmo/                            # Angular HUD: weapon name + ammo + reload bar
    └── PlayerGunsControls/                        # Angular HUD: rebind keys (Tab-safe)
```

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

- [ ] BeamMP testing — the design assumes `electrics.values` are synced (standard BeamMP behavior). Validate in an actual MP session and tune `pg_fire_pulse` overflow handling.
- [ ] Replace `CrashTestSound` per-weapon pitch hack with real OGG fire sounds in `vehicles/unicycle/sounds/`. Infrastructure ready in [`playerGuns.lua`](lua/vehicle/controller/playerGuns.lua) — just drop in files and reference them by path in the weapon table.
- [ ] First-person gun visibility (inherited limitation from `player_weapon_2` — requires camera override, deliberately deferred to stay repo-friendly).
