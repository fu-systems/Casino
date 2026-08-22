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
- **Android** — `casino-android` holds a debug-signed `Casino.apk`
  (arm64, `systems.fu.casino`). Install with `adb install Casino.apk`, or
  copy it across and allow installs from unknown sources.

## Screen sizes

The game is designed at **1280x720** and uses Godot's `expand` stretch
aspect, which treats that as a *minimum* in both directions and grows the
viewport into whatever the device has spare. Nothing is letterboxed and
nothing is clipped:

| Device (landscape) | Window | Viewport |
| --- | --- | --- |
| 4:3 tablet | 2048x1536 | 1280x960 |
| 16:9 phone | 1920x1080 | 1280x720 |
| 20:9 phone | 2400x1080 | 1600x720 |

Roulette is the widest scene at 1258 px, so it fits the 1280 minimum with
22 px to spare. That margin is thin enough to lose by accident, so
`tests/layout_fits.gd` asserts every scene still fits the design viewport —
a layout change that would clip on a 4:3 tablet fails CI instead of
shipping. Run it with:

```bash
godot --headless --path . tests/layout_fits.tscn
```

On mobile the app is locked out of portrait (sensor landscape, so it works
held either way) and insets its UI from notches and camera cutouts via
`scripts/safe_area.gd`.

One honest caveat: the roulette number cells are ~4.8 mm on a phone —
tappable but fiddly. Thirty-seven cells across a handset is inherently
tight, and the real fix is a mobile-specific board layout.

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
- **Hit**, **Stand**, **Double**, or **Split**. Buttons only appear when the
  move is legal and you can cover the extra stake.
- Dealer stands on all 17s and peeks for a natural, so a dealer blackjack
  ends the round immediately rather than letting you draw into it.
- Blackjack pays **3:2** (rounded up, so a $5 blackjack pays $8), wins pay
  1:1, pushes return your bet.

#### Splitting

Any two cards of matching value can be split, up to **four hands**. Each
split hand carries its own stake and is settled against the dealer
independently — you can win one and lose another in the same round. Doubling
after a split is allowed, and raises only that hand's bet.

Split aces get exactly **one card each** and are never re-split. A 21 built
from a split is a plain 21, not a natural, so it pays 1:1 rather than 3:2.

The active hand is outlined in gold, and every hand shows its own total and
stake beneath it.

#### Insurance

When the dealer shows an ace you're offered insurance before the peek. It
costs half your bet and pays **2:1** if the dealer turns over a natural —
exactly cancelling the main bet you just lost. Basic strategy always
declines it; see the count strategy panel for when it's actually worth
taking.

#### The shoe

Cards come from a persistent shoe rather than a fresh deck each hand, which
is what makes counting meaningful. Pick **1 to 8 decks** from the trainer
panel; the dealer reshuffles once the shoe is down to its last **25%**, and
**Shuffle the Shoe** forces it early. Every reshuffle resets the count, just
as it does at a real table. Deck size and shuffling are locked while a hand
is in play.

#### Card counting trainer

Runs a **Hi-Lo** count over every card you have actually seen — the hole
card is excluded until it is turned face up.

| Cards | Value |
| --- | --- |
| 2-6 | +1 |
| 7-9 | 0 |
| 10, J, Q, K, A | -1 |

**Show Count** / **Hide Count** toggles the readout, so you can keep your own
count and check it only when you want to. It shows both the running count
and the true count (running count divided by decks remaining), since index
plays are keyed off the true count. **Clear Count** zeroes the running count
without touching the shoe, for restarting a practice count mid-shoe.

#### Strategy trainer

Two independent show/hide panels, each giving the play and a one-line reason:

- **Basic Strategy** — the correct play ignoring the count, from the standard
  dealer-stands-on-17 chart. *"HIT — Dealer's 10 will usually finish 17 or
  better, so a stiff 16 has to improve."*
- **Count Strategy** — the same decision with index plays from the
  Illustrious 18 applied. *"STAND — Stand on 16 vs 10 at a true count of +0
  or higher, otherwise hit. The count is +3, so stand."* It turns **gold**
  whenever the count actually moves you off basic strategy, so deviations are
  easy to spot.

Both panels advise on the **active** hand, so after a split the advice
follows you from hand to hand. Pairs are advised as a split decision against
the standard double-after-split chart, and during an insurance offer the
panels advise on that instead.

The count panel implements the full **Illustrious 18**: fifteen hard-total
deviations, the two ten-splitting ones, and insurance at true count +3.

### Roulette

- European wheel (single zero, 37 pockets).
- Select a chip value, then click anywhere on the board to place bets:
  - **Straight** (any single number, including 0): pays 35:1
  - **Dozens** and **Columns** (2:1)
  - **Red/Black, Even/Odd, 1-18/19-36** (1:1)
- **Spin** to watch the wheel; winning bets are paid automatically and the
  last ten numbers are shown under the wheel.

#### Repeat until win

**Repeat Until Win** re-stakes the bet currently on the board and keeps
spinning — at roughly five times normal speed — until the spin turns a
profit. "Win" means the spin paid out *more than it cost*, so a partial hit
that still loses money on the round doesn't end the run.

The same button becomes **Stop Repeating** while a run is going, so you can
break out at any time. A run also ends on its own when:

- the bank can't cover the next re-stake, or
- it reaches a safety limit of **250 spins** — press the button again to
  carry on from there.

Winning the last spin doesn't mean the run made money, so the closing
message reports where the whole run finished, not just the spin that ended
it. The board, chips, Spin, Clear Bets, and Back are all locked while a run
is in progress.

## Project layout

| Path | Purpose |
| --- | --- |
| `scripts/bank.gd` | Shared bankroll autoload (`Bank`) |
| `scripts/main_menu.gd` + `scenes/main_menu.tscn` | Lobby |
| `scripts/blackjack.gd` + `scenes/blackjack.tscn` | Blackjack table, shoe, and trainer panel |
| `scripts/blackjack_strategy.gd` | Hi-Lo values, basic strategy, and count index plays |
| `scripts/roulette.gd` + `scenes/roulette.tscn` | Roulette table |
| `scripts/roulette_wheel.gd` | Custom-drawn spinning wheel |
| `scripts/safe_area.gd` | Notch/cutout-aware margin container |
| `tests/layout_fits.gd` | Asserts every scene fits the design viewport |
| `export_presets.cfg` | Linux, Windows, and Android export presets used by CI |
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
3. **Export Android** — builds a debug-signed APK. Godot reads the SDK
   location from Editor Settings rather than the environment, so this job
   generates that file with `--editor --quit` and rewrites the two path keys
   before exporting. It then checks the APK really is one, by looking for
   `AndroidManifest.xml` and `classes.dex` inside it.
4. **Publish release** — on a `v*` tag, zips the builds and attaches them to a
   GitHub release.

A **release-signed** APK needs a real keystore; wire one in through repo
secrets and switch the export to `--export-release` when you want to ship to
the Play Store.

Godot itself exits `0` even when scripts fail to parse, so
`.github/scripts/assert-no-godot-errors.sh` scans the logs instead. It ignores
the Vulkan and ALSA fallback errors that every GPU-less CI runner produces,
while still failing on script and resource errors.

To move to a new engine version, change `GODOT_VERSION` at the top of the
workflow — the editor and export templates are downloaded and cached together
under that key.
