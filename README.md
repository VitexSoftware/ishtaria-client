# ishtaria-client

Godot 4 client of Ishtaria. Distributed as a Debian package (Debian/Ubuntu x86-64); unsigned Windows and macOS builds are exported on request.

**Status:** Heightmap-displaced planet and server-owned scenery, waters and biomes, character creation, accounts, Adventure HUD, inventory/eating, permanent-death obituaries and server-authoritative walking and jumping onto scenery, with original locomotion clips and a third-person camera. Physical arrival animation and in-world grave discovery are not implemented.

## Installation

Debian / Ubuntu (x86-64) only:

```sh
echo "deb http://repo.vitexsoftware.com $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/vitexsoftware.list
sudo wget -O /etc/apt/trusted.gpg.d/vitexsoftware.gpg http://repo.vitexsoftware.com/keyring.gpg
sudo apt update
sudo apt install ishtaria-client
```

## Development

Run directly from the source directory; no export templates are needed:

```sh
make
make run SERVER_URL=http://127.0.0.1:7400
make editor
```

`make` defaults to `run`. Without `SERVER_URL`, the client uses its saved
address or `ISHTARIA_SERVER_URL`. Override the engine with `GODOT`, for example
`make GODOT=tools/godot/godot`, and pass extra engine options with `GODOT_ARGS`.
`make help` lists the available targets. From the parent directory, use
`make -C ishtaria-client`.

Open the folder in Godot 4.5. To build the package:

```sh
sudo apt install godot4 godot4-export-templates
dpkg-buildpackage -us -uc -b
```

Alternatively, `tools/fetch-godot.sh` downloads Godot and its export templates.

If Godot does not find the Debian package's system-wide templates, link them
into its expected user directory before exporting:

```sh
mkdir -p "$HOME/.local/share/godot/export_templates"
ln -s /usr/share/godot4/export_templates/4.5.stable "$HOME/.local/share/godot/export_templates/4.5.stable"
```

To export and run a Linux client directly:

```sh
make build
./build/ishtaria-client.x86_64
```

### Linux arm64, Windows and macOS builds

Linux arm64, Windows (x86-64) and macOS (universal: Apple Silicon and Intel) exports are
defined in `export_presets.cfg` and built from Linux. They need the matching
export templates; `tools/fetch-godot.sh` can fetch them:

```sh
PLATFORMS="linux-arm64 windows macos" tools/fetch-godot.sh
make build-arm64     # build/ishtaria-client.linux-arm64 (standalone, not a .deb)
make build-windows   # build/ishtaria-client.windows-x86_64.exe
make build-macos     # build/ishtaria-client.macos.zip (contains Ishtaria.app)
make build-all       # Linux x86-64 + arm64, Windows, macOS
```

These builds are **not code-signed or notarized**, and they are not tested by the
project: Windows SmartScreen and macOS Gatekeeper will warn (on macOS, right-click →
Open, or `xattr -dr com.apple.quarantine Ishtaria.app`). The Windows executable has
no custom icon or version resource because that needs `rcedit`. The CI job `desktop`
uploads both files as the `desktop` artifact. The supported, packaged target remains
Debian/Ubuntu x86-64.

The connection panel accepts a server address, with **Connect** (or Enter)
and **Disconnect** commands. Bare addresses such as `127.0.0.1:7400` use HTTP;
HTTPS, IPv6 and reverse-proxy base paths are also supported. The last submitted
valid address is saved in Godot's `user://client.cfg` and restored on startup.
`ISHTARIA_SERVER_URL` overrides the startup address without changing the saved
preference. The default is `http://127.0.0.1:7400`.

The client requests `/world` and refreshes the identity every five seconds,
retrying failed connections. Disconnect cancels pending requests and retries;
responses from a previous connection cannot replace the current state. Invalid
addresses do not interrupt an existing connection. This panel manages client
connection settings, not remote server accounts or administrative permissions.

Verify the local server connection without opening a window:

```sh
make run GODOT_ARGS="--headless --max-fps 60 --quit-after 180"
```

A successful connection prints `Connected to Ishtaria server` with the world
identity. This is a smoke check, not an automated assertion of connection success.

Run the automated connection-control checks against the local server:

```sh
make test-connection
```

The test uses a temporary settings file, exercises address submission and both
buttons, and exits nonzero on failure. It does not alter saved user preferences.

## Player Setup

Startup first connects to the saved server, leaving server controls accessible
while connecting or unavailable. Once the world is verified, first launch opens
**New player** with a nickname, optional password, and 12 appearances
from Kenney's Protagonists, Retro and Survivors packs. The preview uses the actual
FBX models, selected skins and idle animation; its rotation slider turns the model.
**Create player** registers the selected character on the connected server.
**Change server** clears the form and disconnects, returning to server selection.
**Player** reopens setup or sign-in only after a verified connection.

Nicknames use 3-32 ASCII letters, digits, `_` or `-`, and passwords contain
either zero or 8-128 UTF-8 bytes. An empty password leaves the character unprotected:
anyone knowing its nickname can sign in by leaving the password empty.
Remote accounts require HTTPS; plain HTTP is permitted only
for `localhost`, `127.0.0.1` and `::1`. Authentication redirects are disabled.
The server must provide the `/players` API and apply its embedded migrations.

The successful nickname and character are remembered in the local `[player]`
section of `user://client.cfg`. Subsequent launches and reconnections automatically
open **Sign in** with the remembered nickname after server verification, not
**New player**. Logout also returns to sign-in; authentication is never automatic.
Passwords and session tokens
are never written to settings. Tokens exist only in memory and are cleared on
disconnect, server change or logout. **Sign out** also revokes the server session.

The HUD uses the authenticated server profile and refreshes it every ten seconds.
New accounts receive 100 gold exactly once. Login and refresh never regrant it,
and gold is displayed as an exact decimal string. Guest mode shows unavailable
values rather than inventing a player. Language and interface sound preferences
remain exclusively client-local and do not reconnect or update the player record.

The compact bottom HUD is centred and capped at 920 pixels. Slim coloured bars
show health, stamina, food and water, switching to two columns on narrow windows.
The solar clock and progression remain below them, with icon-only inventory,
settings and sound controls above. Long names and amounts keep their complete
values in tooltips. Selected Kenney RPG textures and a subdued fantasy border
provide the framing without changing the server-owned data.

### Approach To The Player Location

Successful registration or login starts a four-second camera rotation and descent
toward the authoritative `position` in the profile. A new character's random point
comes from the server and is persisted; returning characters approach the same
saved location. The sky blends from the server's space sky into its surface sky.
Once terrain is loaded, the selected character appears at the saved position and
the camera switches to third-person controls. Profile refreshes do not restart
the transition. Logout, death or server change cancels it and restores the orbit.
Missing or invalid positions leave the client in orbit with visible feedback;
the client never guesses a random destination to hide missing server integration.

The planet shades the six-face PNG from `/world/heightmap.png` using the inverse
spherified-cube mapping matching worldgen. Downloads are bounded, dimensions are
verified before decoding, and stale responses cannot replace a newly selected
world. Heights displace the sphere using the default worldgen 8000-metre amplitude.
Cube faces use north-up pixel-center coordinates, matching the PNG and PGM.
This remains finite-resolution terrain, not full Earth-scale procedural detail
or a physical landing simulation.

### Character And Camera Controls

WASD walks relative to the camera heading; diagonal movement is normalized.
Hold Shift to run at 6 metres per second instead of walking at 4; release it
to return to walking. Press I to open the existing inventory and release the
cursor. Inventory and other game panels stop walking and running input.
Space jumps once per press. Hold a walking direction at the press to launch in
that direction, or jump vertically without one. The unobstructed apex is about
2.15 metres normally or 3.68 metres while running in a direction; running jumps
also stay airborne longer and travel farther. Shift alone does not boost a stationary jump.
Reachable rocks and elevations support the character after landing.
The launch direction and walking/running speed are retained in flight;
holding Space cannot repeat the jump.
Move the mouse to orbit the character and use its wheel to zoom between
2 and 30 metres. The camera stays above sampled terrain and keeps the avatar
above the HUD, including narrow windows. Escape releases the cursor and stops
walking. Clicking unobstructed scenery captures it again. Opening game panels
or losing application focus also releases the cursor.

Open the HUD gear and choose **Controls** to rebind the four physical keys,
adjust mouse sensitivity, invert vertical mouse movement or restore defaults.
Click a binding and press its replacement; Escape cancels capture. Conflicting
bindings swap rather than assigning one key to two directions. These preferences
reserve Shift for running, I for inventory, Space for jumping and Escape for releasing the cursor, and
are saved in the local `[controls]` section without altering server, language
or account settings.

The client sends intentions every 100 ms, never a trusted destination or elapsed
time. Only accepted server responses move the avatar; saved position survives
login and restart. Rendering smoothly interpolates only acknowledged positions,
without predicting or extrapolating movement. Camera clearance, height sampling
and terrain projection use scalar double precision before constructing local
vectors, avoiding planet-scale half-metre quantization. After interpolation,
the grounded avatar is projected onto the actual local terrain triangles,
including while idle. Airborne or object-supported acknowledgements retain
the authoritative height instead. This keeps the original model's ground origin on the
rendered surface despite mesh interpolation or a saved height from an older
terrain version; it does not overwrite authoritative position targets or send
client-computed destinations to the server. Scenery refreshes after moving
100 metres.
Walking is limited to dry, non-steep terrain and cannot cross solid scenery.
The original Kenney `run.fbx` clip supplies locomotion, retargeted to the selected
character and scaled to acknowledged speed. Actual displacement starts it;
blocked movement, stale acknowledgements and released input return to idle.
Swimming is not implemented. Movement or object-download failures
show feedback in the connection panel and stop walking input.

```sh
make test-controls
godot4 --path . --max-fps 60 --script res://tests/character_controls.gd
```

The native test uses read-only local world data and a test-only avatar. It captures
the camera and Czech settings at 1600x900, 640x480 and 360x640 under
`/tmp/ishtaria-controls-*.png`, without changing a live player or user preferences.

To replay the server's steep-stone slide and saved-overlap recovery regression,
first export its verified trajectory, then run the same native test:

```sh
(cd ../ishtaria-server && ISHTARIA_SLIDE_CAPTURE=/tmp/ishtaria-slide-capture.json cargo test --locked descending_capsule_slides_off_steep_rock_without_getting_stuck)
ISHTARIA_SLIDE_CAPTURE=/tmp/ishtaria-slide-capture.json godot4 --path . --max-fps 60 --script res://tests/character_controls.gd
```

The isolated test trajectory is relocated onto local world terrain for rendering;
no live player is moved. Screenshots are saved as `/tmp/ishtaria-slide-*.png`.

### Day And Night

The server's version-1 `solar` state drives a real-time Earth-like solar cycle.
The client checks its timestamp, direction and model parameters, then continues
with monotonic elapsed time. Reconnecting samples the current server time;
changing local wall-clock settings does not alter the cycle. Legacy servers
without solar metadata retain their fixed lighting.

Sun position uses sidereal rotation, orbital motion and axial tilt, with local
horizons defined by the camera's planet-fixed position. Mean solar days last
24 real hours; latitude and season determine day length and polar day/night.
The visible solar disc and directional lighting share one direction. Its
approximately half-degree diameter changes with orbital distance. Twilight,
warm low-angle sunlight, dark night ambient light and fog follow solar elevation;
the orbital view keeps a dark night side. Horizon dip follows observer altitude,
with approximate near-horizon refraction. Kenney skies remain the backgrounds;
their baked solar/lunar discs are masked in dynamic mode without modifying the
original assets.

This uses a low-order solar ephemeris and stylized atmospheric colors, not full
atmospheric scattering, lunar physics, eclipses or seasonal weather simulation.

The HUD shows local solar time and an hours/minutes countdown to sunrise at
night or sunset during the day. It follows the server clock and observer
location, not the operating-system timezone. Events use the standard -0.833-degree
solar horizon; nearby terrain and atmospheric variations are not predicted.
If no event occurs within the next 24 hours, including polar day/night, the HUD
states that instead of inventing a countdown. Missing solar metadata shows
**Time unavailable**. The clock updates once per second; event prediction is cached.

```sh
make test-day-night
godot4 --path . --max-fps 60 --script res://tests/day_night.gd
```

The native test captures day, sunset and night at 1600x900, 640x480 and 360x640
under `/tmp/ishtaria-{day,sunset,night}-WIDTHxHEIGHT.png`, checks the visible
disc and day/night contrast, and rejects a baked duplicate sun. Headless checks
cover metadata validation, opposite longitudes, polar seasons and disconnect.
Clock HUD captures use `/tmp/ishtaria-clock-{day,sunset,night}-WIDTHxHEIGHT.png`
and also check Czech countdown text and layout containment.

### Terrain And Scenery

The client also requests `/world/environment` and checks its version, checksum,
exact string seed, array bounds and values before using it. The server determines
sea level, lake spill levels, river drainage and biomes. Requests are bounded,
cancelled on disconnect, reject stale responses and retry on identity refresh.
An older server without this endpoint still displays terrain and sea, but cannot
provide forests, lakes or rivers. Rebuild/restart the server before testing them.

Environment version 2 adds seeded, globally continuous local relief of at most
12 metres in either direction, fading out near sea level. It is shared with
server walking, object placement and new spawns; version 1 retains base heights.
The imported heightmap is unchanged. The local 128-by-128-cell indexed mesh uses
exact origin subtraction, separate land/water vertices and stable local wave
phases. The shader does not displace these projected vertices a second time.

A detailed 1.4-km-wide surface patch and at most 512 nearby objects appear around
the server-owned player location. `/world/objects?x=...&y=...&z=...` supplies bounded
descriptors in metres with matching terrain checksum and seed. The client validates
them and renders their exact positions; it does not invent local replacements.
Objects use a global cube-face grid, with seed and cell-derived IDs, position
jitter, orientation and scale. Forest density,
biome rules, slope limits and water checks control placement. Returning to the
same region with the same seed and catalog reproduces it. Object scenes are
visual representations of server-owned footprints, not client-created inventory,
resources, buildings or game balances. Swept collisions block trees, rocks,
bushes and plants; decorative grass, flowers and mushrooms remain passable. Arrival waits for object
data, refresh retains the previous region until its replacement arrives, and
cancelled or stale replies cannot replace another world.
Rivers follow the server's coarse drainage tree; lakes use its flat spill levels.
The finite preview does not simulate river erosion or metre-scale hydrology.

Nature Kit contributes all 161 natural variants: broadleaf trees, pines, palms,
large/small/tall rocks and stones, bushes, grass, flowers, mushrooms, logs, stumps
and cacti. Family weights prevent a family with many variants from dominating
selection. Original GLB transforms are retained and measured for footprints;
tree footprints use their lower trunk rather than the canopy. Modular cliff,
river/path, bridge, fence, campsite and farming pieces are not scattered as
natural resources or claimed as implemented gameplay.

To reproducibly synchronize the natural models from the original CC0 archive:

```sh
node tools/sync-nature-catalog.mjs /path/to/nature-kit.zip ../ishtaria-server/etc/world_objects.json
godot4 --headless --path . --editor --import
```

Extend [`assets/world_objects.json`](assets/world_objects.json) with any
Godot-importable 3D `PackedScene` (GLB/glTF, imported OBJ/FBX, or a `.tscn`):

```json
{"id":"custom.tree","scene":"res://assets/custom/tree.glb","biomes":["forest"],"weight":2,"scale_m":1,"max_slope":0.5}
```

Add the same ID, numeric biome IDs, selection parameters and a measured normalized
`collision_radius` to the server's embedded `etc/world_objects.json`, then rebuild
the server. The server selects the model and supplies its final scale and position.
Keep IDs unique and paths local. `scale_m` maps one authored model unit to metres;
Godot preview units are kilometres. Author the origin at the object's base and
its up axis as +Y; retain other model transforms inside the scene. `weight`
controls model selection and `max_slope` is rise/run. The optional `metallic`
override is applied to duplicated standard materials, leaving original assets
intact. It corrects the Nature Kit's fully metallic exports. Scene hierarchies
are instantiated intact rather than reduced to a hardcoded tree mesh. Custom
animation and gameplay still need their own authoritative integration. Walking
uses base circles; jumping uses the original triangle geometry, not general
rigid-body physics. Regenerate the embedded collision geometry after model changes:

```sh
godot4 --headless --path . --script res://tools/export-world-colliders.gd -- ../ishtaria-server/etc/world_colliders.json
```

Then rebuild the server. Changing the server catalog
weights/content may change the model chosen for a cell; keep the client model IDs
compatible with the server catalog.

Run focused checks and native screenshots:

```sh
make test-environment
godot4 --path . --max-fps 60 --script res://tests/surface_environment.gd
ISHTARIA_ENVIRONMENT_TEST_URL=http://127.0.0.1:PORT make test-environment
```

The optional HTTP check is read-only and expects a generated map containing all
eight biomes. Native checks capture forest, snow, mountains and lakes at
1600x900, 640x480 and 360x640 in `/tmp/ishtaria-environment-*.png` and inspect
pixels. They do not replace a physical landing or full Earth-resolution test.

Server controls hide during an authenticated approach to leave the planet visible.
The Kenney gear icon in the HUD toggles them without reconnecting or cancelling
the approach; open it to change server or sign out.

### Inventory And Memorials

Inventory shows the server-owned capacity, exact stacks and food calories.
Edible items offer **Eat**; the client sends only the item identifier.
Eating when already fully fed restores five health, capped at 100. Movement
acknowledgements update the HUD's server-owned stamina, water and health.
Long walks consume stamina; running consumes it five times faster and uses more
water. At zero stamina the server allows only walking, which slowly damages
health; zero water also damages health. After five seconds standing still,
stamina starts recovering. Drinking is not implemented yet.
Death is permanent. Attempting to sign in with the deceased character's correct
password shows **In Memoriam**, with name, lived days, lifetime accumulated gold
and friends at death, but never restores a session. **New character** opens
fresh registration with an empty nickname and password, not a resurrection.

The same obituary appears in contextual grave interaction, together with the
remaining possessions. It persists even after the grave has been emptied.
There is no **Graves** section or global browser. The server requires a living
character within three authoritative position units to inspect or take items.
Nearby headstones, monuments and mausoleums appear at saved death positions using
the bundled Graveyard Kit. The server selects their kind from lifetime earnings;
the client refreshes nearby memorials every five seconds, also while stationary.
Grave collision and click-to-inspect interaction are not integrated yet;
the protected inventory API is not yet a complete playable recovery journey.
Friendship management is also still planned. Numeric obituary statistics remain
decimal strings, preserving large gold amounts exactly.

Run isolated client checks (no account or production data is created):

```sh
make test-characters
godot4 --path . --max-fps 60 --script res://tests/character_creation.gd
```

The native test captures Czech setup at 1600x900, 640x480 and 360x640 under
`/tmp/ishtaria-character-cs-*.png`. It verifies model and skin loading, animation
motion, preference restoration, stale-response rejection and control bounds.
It also captures inventory, each memorial model and obituaries under
`/tmp/ishtaria-inventory-cs-*.png`, `/tmp/ishtaria-grave-*.png` and
`/tmp/ishtaria-obituary-cs-*.png`, including small-window text bounds.
For an actual HTTP registration/login/logout test, set
`ISHTARIA_PLAYER_TEST_URL=http://127.0.0.1:PORT` to a separately started test
server backed by a disposable database, then run `make test-characters`.
This optional test creates test accounts: never point it at a live game server.

## Story characters

When the connected world has story datadisks, their characters stand in the world (Kenney character models,
named above the head in the chosen language). `E` talks to the nearest one: the dialogue panel shows the
character's portrait and speech and plays the conversation's music (switched with the HUD sound button).
Portraits and music are fetched from the server (`/story/media/...`), kept in memory only and never bundled with
the client. `make test-story` runs the offline checks; `make test-world-view` (display and a running server needed, `ISHTARIA_TEST_SERVER`) starts the real client, registers a character and saves screenshots of the spawn and the dialogue to `ISHTARIA_SHOT_DIR`.

## Localization

English is the source and default language. Select **English** or **Čeština**
in the connection panel to change the interface language immediately, including
connection status and error messages.

The preference is stored only in the client's `user://client.cfg`, under
`[interface]` as `language="en"` or `language="cs"`. It is restored on startup
and is never sent to the server or stored in a player account. Changing language
does not reconnect the client. Unsupported saved values fall back to English.

Translations are maintained in [`locales/client.csv`](locales/client.csv),
which Godot imports into its native translation resources. Server addresses,
world identities and ruleset identifiers are not translated.

`make test-connection` also verifies language switching, translated messages
and local preference persistence.

License: MIT

## Credits and Thanks

Thanks to [Kenney](https://kenney.nl/) for making high-quality game assets
freely available, and to the [Godot](https://godotengine.org/) contributors
for the open-source engine powering this client.

The client includes resources from:

- [Starter Kit Basic Scene](https://github.com/KenneyNL/Starter-Kit-Basic-Scene): scene and environment setup under MIT; Mini Arena models under [CC0](https://creativecommons.org/publicdomain/zero/1.0/), with additional credit to Tony Schär.
- [Skyboxes](https://kenney.nl/assets/skyboxes): surface-sky panoramas under CC0.
- [Skyboxes Space](https://kenney.nl/assets/skyboxes-space): space panoramas under CC0.
- [Mini Forest](https://kenney.nl/assets/mini-forest): selected trees, plants and rocks under CC0.
- [Platformer Kit](https://kenney.nl/assets/platformer-kit): selected pines, snow pines and rocks under CC0.
- [Animated Animal Pack](https://poly.pizza/bundle/Animated-Animal-Pack-ILAPXeUYiS) by Quaternius: all 12 animals under CC0, standing in the world and as inventory items, in `assets/quaternius/animated-animal-pack/`.
- [Animated Fish Bundle](https://poly.pizza/bundle/Animated-Fish-Bundle-44zhHN1UbT) by Quaternius: its 35 fish (not the boat, docks, rods, lures or worm) under CC0, swimming in oceans, lakes and rivers, in `assets/quaternius/animated-fish-bundle/`.
- [Ultimate RPG Items Bundle](https://poly.pizza/bundle/Ultimate-RPG-Items-Bundle-h8mhlZ0dG8) by Quaternius: all 55 models (weapons, armour, shields, potions, keys, books, valuables) under CC0, in `assets/quaternius/ultimate-rpg-items/`.
- [Survival Kit](https://kenney.nl/assets/survival-kit): selected trees, rocks and grass, plus the axe, pickaxe, log, wood, plank and stone models, under CC0. Inventory icons in `assets/icons/items/` are rendered from these models with `tools/bake-item-icons.gd`.
- [Nature Kit](https://kenney.nl/assets/nature-kit): all 161 natural model variants under CC0, with original transforms and licence.
- [Interface Sounds](https://kenney.nl/assets/interface-sounds): interface feedback audio under CC0.
- [UI Pack Adventure](https://kenney.nl/assets/ui-pack-adventure): HUD panels, meters and checkboxes under CC0.
- [Fantasy UI Borders](https://kenney.nl/assets/fantasy-ui-borders): selected decorative HUD border under CC0.
- [UI Pack (RPG Expansion)](https://kenney.nl/assets/ui-pack-rpg-expansion): HUD surface and small button states under CC0.
- [Animated Characters Protagonists](https://kenney.nl/assets/animated-characters-protagonists): model, four skins, idle and run animations under CC0.
- [Animated Characters Retro](https://kenney.nl/assets/animated-characters-retro): model, four skins, idle and run animations under CC0.
- [Animated Characters Survivors](https://kenney.nl/assets/animated-characters-survivors): model, four skins, idle and run animations under CC0.
- [Food Kit](https://kenney.nl/assets/food-kit): apple, bread, cheese and carrot previews under CC0.
- [Flag Pack](https://kenney.nl/assets/flag-pack): the English (GB) and Czech (CZ) flags beside the language choice under CC0.
- [Fantasy Town Kit](https://kenney.nl/assets/fantasy-town-kit): houses, roofs, roads, fountain, stalls and trees of generated towns under CC0.
- [Castle Kit](https://kenney.nl/assets/castle-kit): town walls, gates and towers under CC0.
- [Retro Fantasy Kit](https://kenney.nl/assets/retro-fantasy-kit): trees, barrels and crates in towns and harbours under CC0 (`tools/bundle-scenery.py` copies the used models).
- [Pirate Kit](https://kenney.nl/assets/pirate-kit): harbour huts, piers, boats and ships under CC0.
- [Graveyard Kit](https://kenney.nl/assets/graveyard-kit): headstone, obelisk, crypt parts and their texture under CC0.
- [Game Icons](https://kenney.nl/assets/game-icons): inventory, connection settings and audio controls under CC0.

Original license notices are retained alongside the bundled resources in
[`assets/kenney/`](assets/kenney/). These third-party resources retain their own
licenses; the client's MIT license does not replace them.

## Part of Ishtaria

Ishtaria is an open-source, persistent, federated virtual planet of Earth size.
Documentation: https://vitexsoftware.github.io/ishtaria-docs/ · All repositories: https://github.com/VitexSoftware?q=ishtaria
