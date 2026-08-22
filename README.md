# Casino

[![Build](https://github.com/fu-systems/Casino/actions/workflows/build.yml/badge.svg)](https://github.com/fu-systems/Casino/actions/workflows/build.yml)

A small casino game built with **Godot 4** — blackjack and European roulette,
sharing one bankroll.

## Download a build

Every push builds Linux and Windows executables. Grab them from the
**[Actions tab](https://github.com/fu-systems/Casino/actions/workflows/build.yml)**
— open the most recent run and download `casino-linux-x86_64` or
`casino-windows-x86_64` from the Artifacts section. Tagged releases
(`v*`) also attach both zips to the GitHub release.

The builds are self-contained: the game data is embedded in the executable,
so there's nothing to install.

- **Linux** — `chmod +x Casino.x86_64 && ./Casino.x86_64`
- **Windows** — run `Casino.exe`

## Running from source

1. Install [Godot 4.5 or newer](https://godotengine.org/download) (the standard
   build — no C#/.NET required).
2. Open the Godot Project Manager, click **Import**, and select this folder's
   `project.godot`.
3. Press **F5** (or the Play button) to run.

You start with a **$1,000** bankroll shared between both games. You can reset
it from the main menu at any time.

## Games

### Blackjack

- Place a bet with the chip buttons, then **Deal**.
- **Hit**, **Stand**, or **Double** (double is available on your first two
  cards if you can cover the extra bet).
- Dealer stands on all 17s and peeks for a natural, so a dealer blackjack
  ends the round immediately rather than letting you draw into it.
- Blackjack pays **3:2** (rounded up, so a $5 blackjack pays $8), wins pay
  1:1, pushes return your bet. No splits or insurance — this is the simple
  table.

### Roulette

- European wheel (single zero, 37 pockets).
- Select a chip value, then click anywhere on the board to place bets:
  - **Straight** (any single number, including 0): pays 35:1
  - **Dozens** and **Columns** (2:1)
  - **Red/Black, Even/Odd, 1-18/19-36** (1:1)
- **Spin** to watch the wheel; winning bets are paid automatically and the
  last ten numbers are shown under the wheel.

## Project layout

| Path | Purpose |
| --- | --- |
| `scripts/bank.gd` | Shared bankroll autoload (`Bank`) |
| `scripts/main_menu.gd` + `scenes/main_menu.tscn` | Lobby |
| `scripts/blackjack.gd` + `scenes/blackjack.tscn` | Blackjack table |
| `scripts/roulette.gd` + `scenes/roulette.tscn` | Roulette table |
| `scripts/roulette_wheel.gd` | Custom-drawn spinning wheel |
| `export_presets.cfg` | Linux + Windows export presets used by CI |
| `.github/workflows/build.yml` | Check, export, and release pipeline |
| `.github/actions/setup-godot/` | Composite action that installs Godot + templates |

All UI is built in code from plain Control nodes, so there are no binary
assets — the whole game is readable GDScript.

## Building locally

Godot cross-compiles Windows binaries from Linux, so one Godot install
produces both. With the editor and matching export templates installed:

```bash
godot --headless --import --path .
godot --headless --path . --export-release "Linux"   "$PWD/build/Casino.x86_64"
godot --headless --path . --export-release "Windows" "$PWD/build/Casino.exe"
```

`--export-release` takes the **preset name** from `export_presets.cfg`
(`Linux` / `Windows`), not the platform name.

## Continuous integration

`.github/workflows/build.yml` runs on every push, pull request, and manually
via *Run workflow*:

1. **Check** — imports the project and boots it headless, failing the build on
   any parse or runtime script error.
2. **Export** — builds Linux and Windows in parallel and uploads each as an
   artifact.
3. **Publish release** — on a `v*` tag, zips both builds and attaches them to a
   GitHub release.

Godot itself exits `0` even when scripts fail to parse, so
`.github/scripts/assert-no-godot-errors.sh` scans the logs instead. It ignores
the Vulkan and ALSA fallback errors that every GPU-less CI runner produces,
while still failing on script and resource errors.

To move to a new engine version, change `GODOT_VERSION` at the top of the
workflow — the editor and export templates are downloaded and cached together
under that key.
