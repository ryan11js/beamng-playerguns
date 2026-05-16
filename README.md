# PlayerGuns

A BeamNG.drive mod that lets the player equip and shoot guns while in Walking Mode (i.e. outside a vehicle). **Architecture adapted from** [`player_weapon_2`](https://www.beamng.com/threads/player-weapons-2.94445/) by AwesomeCarl & AgentY, **with added BeamMP multiplayer support**.

## Features

- Four weapons: **Uzi**, **Thompson**, **AKM**, **Bazooka** (state-machine, switch on the fly; correct mesh shows per weapon).
- **Camera-based aim** with per-weapon recoil spread (Uzi spray, AKM controlled, Bazooka near-perfect).
- **Physics bullets** with damage that breaks beams on the target vehicle — pops tires, dents panels, rocks the suspension.
- **Bazooka does AoE damage** — 2.5m blast radius with fireball particles.
- **Two HUD apps**: a centered Crosshair and a bottom-right Ammo box. Place each independently.
- **Snowman body** option (or stay invisible).
- **BeamMP-compatible**: aim syncs via `electrics`, fire-pulse counter replays shots on remote clients.

## Controls

Default keybinds (v0.5.3+):

| Action | Default |
|---|---|
| Fire | Left Mouse Button |
| Reload | Q |
| Previous Weapon | O |
| Next Weapon | P |

You can rebind these in Options → Controls → Vehicle (search "PlayerGuns") if needed.

**If your saved binds get clobbered** (BeamNG sometimes resets template bindings on vehicle-context switches), delete `Documents\BeamNG.drive\<version>\settings\inputmaps\{keyboard0,mouse0}.diff` and relaunch — the defaults above will reload.

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
4. Open the UI app menu (Ctrl+U) and add **Player Guns Crosshair** (center of screen) and **Player Guns Ammo** (bottom-right) to your screen. Both apps subscribe to the same controller stream — you can place them independently or omit either one.
5. Aim with the mouse, fire with your bound key. Switch weapons with your bound keys.

> The "Invisible Body" name is honest: picking this variant hides the beamling/snowman/debug body and you'll only see the floating gun. This is the simplest pattern the BeamNG slot system allows (a body part *replaces* the body — it doesn't extend it). A future version can add a "PlayerGuns Armed (Beamling)" variant that keeps the default body mesh.

## File Layout

```
PlayerGuns/
├── mod_info/info.json
├── lua/vehicle/controller/playerGuns.lua          # main controller (camera-aim + physics bullets + MP sync)
├── vehicles/unicycle/
│   ├── input_actions_playerGuns.json              # vehicle-scoped input actions
│   ├── inputmaps/                                 # default keyboard + mouse binds
│   ├── playerGuns_body.jbeam                      # body variant, fills stock unicycle_meshes slot; exposes weapon sub-slot
│   ├── playerGuns_main.jbeam                      # weapon system part, fills playerGuns_weapon sub-slot
│   ├── playerGuns_ammo.jbeam                      # 100 bullet nodes, fills playerGuns_ammo sub-slot
│   ├── playerGuns.materials.json                  # PBR materials
│   ├── playerGuns_models.dae                      # gun mesh (Uzi/Thompson/AKM/Sniper/Bazooka/etc)
│   └── textures/                                  # PBR textures
└── ui/modules/apps/
    ├── PlayerGunsCrosshair/                       # Angular HUD: center-screen crosshair
    └── PlayerGunsAmmo/                            # Angular HUD: weapon name + ammo + reload bar
```

## How Multiplayer Works

The original `player_weapon_2` mod doesn't work in BeamMP because its camera direction is fetched locally from `core_camera.getForward()` (a game-engine call), and that state isn't synced. PlayerGuns fixes this by:

1. Writing the aim vector into `electrics.values.pg_aim_x/y/z` every frame. BeamMP syncs electrics, so remote clients see where the shooter is pointing.
2. Gating input handling (LMB / R / Q / E) to `v.mpVehicleType == "L"` so only the local owner runs firing logic.
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
