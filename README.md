# Casino

A small casino game built with **Godot 4** — blackjack and European roulette,
sharing one bankroll.

## Running the game

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (the standard
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
- Dealer stands on all 17s. Blackjack pays **3:2**, wins pay 1:1, pushes
  return your bet. No splits or insurance — this is the simple table.

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

All UI is built in code from plain Control nodes, so there are no binary
assets — the whole game is readable GDScript.
