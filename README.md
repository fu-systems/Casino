# Casino

[![Build](https://github.com/fu-systems/Casino/actions/workflows/build.yml/badge.svg)](https://github.com/fu-systems/Casino/actions/workflows/build.yml)

A small casino game built with **Godot 4** — blackjack, European roulette,
craps and baccarat, sharing one bankroll of free play money.

It's also an honest one. It prints the house edge, explains the right play,
and sells no chips: everything here is free, and the only things for sale
are optional one-time packs — trainers for blackjack and labs for testing
betting systems — plus a tip jar. See [Play money, and what's for
sale](#play-money-and-whats-for-sale).

## Download a build

Every push builds Linux and Windows executables. Grab them from the
**[Actions tab](https://github.com/fu-systems/Casino/actions/workflows/build.yml)**
— open the most recent run and download `casino-linux-x86_64` or
`casino-windows-x86_64` from the Artifacts section. Tagged releases
(`v*`) also attach both zips to the GitHub release.

The builds are self-contained: the game data is embedded in the executable,
so there's nothing to install. On desktop, **F11** or **Alt+Enter** switches
fullscreen, and the game remembers which you chose.

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
22 px to spare; craps is the tallest at 663 px of the 720. Both margins are
thin enough to lose by accident, so `tests/layout_fits.gd` asserts every
scene still fits the design viewport — a layout change that would clip on a
4:3 tablet fails CI instead of shipping. It runs as part of the suite:

```bash
godot --headless --path . res://tests/run_all.tscn
```

On mobile the app is locked out of portrait (sensor landscape, so it works
held either way) and insets its UI from notches and camera cutouts via
`scripts/safe_area.gd`.

Two honest caveats, both about density rather than correctness. The roulette
number cells are ~4.8 mm on a phone — tappable but fiddly; thirty-seven
cells across a handset is inherently tight. The craps felt is tighter still:
faithful table proportions mean a thin don't pass band and a curved apron,
which are harder to thumb accurately than rectangles would be. Exact polygon
hit-testing at least stops neighbouring areas stealing taps, but in both
cases the real fix is a mobile-specific board layout rather than a scaling
tweak.

## Running from source

1. Install [Godot 4.5 or newer](https://godotengine.org/download) (the standard
   build — no C#/.NET required).
2. Open the Godot Project Manager, click **Import**, and select this folder's
   `project.godot`.
3. Press **F5** (or the Play button) to run.

You start with a **$1,000** bankroll shared between every game. It's saved
between launches, and you can reset it from the main menu at any time.

## Play money, and what's for sale

The first launch says it plainly: Casino is a simulation for adults (18+),
played with chips that are free, unlimited and worth nothing — they can't be
bought, won or cashed out. The lobby says it again in its footer, and its
**About** box carries the privacy statement ([PRIVACY.md](PRIVACY.md): no
data collected) and links to problem-gambling help.

**Extras** in the lobby lists everything optional:

| | | Price |
| --- | --- | --- |
| Strategy charts | Blackjack — basic strategy and the Illustrious 18 | free |
| Coin Flip | Baccarat — the game shown as the coin flip it is | free |
| Strategy Trainer | Blackjack — drills on every decision | pack |
| Card Counting Trainer | Blackjack — tap-to-deal counting drills | pack |
| Roulette Systems Lab | Build and test betting systems | pack |
| Craps Systems Lab | The same, for the dice | pack |
| Tip jar | Changes nothing; says thank you | tip |

Packs are one-time purchases through Google Play, restorable on any device.
Nothing that was free went behind a paywall, nothing nags, and nothing sells
chips; [docs/PLAY_RELEASE.md](docs/PLAY_RELEASE.md) has the full list of
rules the code keeps, and how to publish. Builds that have no store to buy
from — the desktop builds and the debug APK — come with every pack unlocked.

The **Steam edition** is sold once with everything included: every pack, no
tip jar, and saves synced by Steam Cloud. It's the desktop game exported with
the `steam` feature, and it starts fullscreen. The free builds here stay free
and complete. [docs/STEAM_RELEASE.md](docs/STEAM_RELEASE.md) covers the
store page, depots, Steam Cloud and the Deck.

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

#### Strategy charts (free)

**Strategy Charts**, at the bottom of the trainer panel, opens the whole of
basic strategy — hard totals, soft totals and pairs against every upcard —
and the Illustrious 18 as a table of indices. They open over the table, so
the shoe and the count are still there afterwards. No cell is typed in: each
one asks the same strategy code the hints use about a real hand, so a chart
can never disagree with the advice at the table.

#### Strategy Trainer (pack)

A hand, an upcard, sometimes a count: what's the play? **Basic** covers every
chart decision, three-card hands that can't double included. **Count** sits
on the Illustrious 18, at true counts either side of each index, plus
insurance. **Weak Spots** asks about the cells you miss most, remembered
between sessions. **Blitz** gives you 60 seconds. Right answers score, with a
multiplier for a streak; a wrong one stops to show the right play, the
reason, and the cell on the chart.

#### Card Counting Trainer (pack)

A dealer and up to seven players who all play basic strategy, dealt from the
same shoe as the table. Every tap lays the next card in table order — round
the table twice, the hole card face down until it turns over, each seat's
hits, doubles and splits, then the dealer — so you set the pace, inside a
time limit per round (Relaxed, 20, 10 or 6 seconds). When the round ends you
enter the running count on a number pad, and optionally the true count
against the discard tray. A miss or a timeout ends the run, and the summary
replays the round card by card with each card's Hi-Lo value. The best cards
counted and the best pace are kept for each time limit.

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

#### Systems Lab (pack)

Build a betting system as a flowchart and play it for thousands of spins.
A system is a set of **steps**. Each step has its bets, in units, and a list
of **IF / THEN** rules checked after every spin: the first rule that matches
runs, and if none does the step's OTHERWISE does.

- **Conditions:** the round won, lost or pushed; a bet winning or losing;
  several bets together (all, any, none, exactly N or at least N of them); a
  run of results ("red the last five spins"); the zero; and comparisons on
  the win and loss streaks, the bankroll, the session's net, the unit, the
  rounds played and two counters — combined with and, or and not.
- **Actions:** set or change a bet, change the unit (reset, set, add,
  multiply), go to a step, change a counter, sit out, or stop.

Everything is built from dropdowns, steppers and a miniature board, and the
**Flowchart** tab draws the system as boxes and labelled arrows. Nine famous
systems open as editable copies — flat, Martingale, Paroli, D'Alembert,
Fibonacci (as a ladder of steps), two dozens, wait-for-five-reds, a triple
cover, and Repeat Until Win — and systems save by name and share as a line of
text. The **Systems Lab** button on the table brings the chips on the table
with it as a starting system.

**Results** plays one session with a spin-by-spin trace (which step, which
rule fired, why), or many sessions as a histogram: how often it finished
ahead, how often it ran short of its next bet, the average, the median, the
best and the worst. Every result sits beside what the 2.7% edge predicts on
the money staked — over enough spins the two agree, whatever the system.

### Craps

Laid out as a real table: the point boxes across the top with the don't come
box at their end, the come band beneath, the field, and the pass line
hooking around the outer corner with don't pass running parallel just inside
it. Big 6/8 splits a square on the diagonal, and the stickman's proposition
box sits to the side with dice pips printed on the hardways and the one-roll
numbers. The white **ON** puck sits on the point; between points the black
**OFF** puck is parked in the don't come box.

Chips land where chips land on a table — place bets on the bottom line of a
box, come bets inside it, don't come bets in the strip above the number, and
odds heeled beside their flat bet.

A real table prints no house edge anywhere, so neither does this one.
**Show Edges** puts them all back: craps runs from 1.41% on the pass line to
16.7% on Any 7, and that spread is the single most useful thing to know
about the game.

Payouts are printed **TO 1**, not the casino's **FOR 1**. They are not the
same thing — 30 *for* 1 returns 30 including your stake, which is 29:1. This
game pays 30 *to* 1, so printing the casino's wording would misstate its own
payout.

House rules, stated on screen because they change what a bet does:

- Place bets and every odds bet are **off on the come-out roll** — they
  neither win nor lose, and wait there for a point.
- Odds are capped **3-4-5x** (3x on the 4 and 10, 4x on the 5 and 9, 5x on
  the 6 and 8), so the most you can win behind the line is six times it
  whatever the point. **Max Odds** tops every odds bet up to its cap.
- **Winners stay up.** As on a live table, a paid bet keeps working — the
  line, place bets, the field, hardways and the props are all paid and left
  standing (the horn and C & E stay whole, their losing portions bought
  back out of the winnings). The exceptions are the real ones: a come bet
  that made its number comes down with its pay, and so do odds once their
  point resolves. On the bar twelve the don't side neither wins nor loses —
  it just stands off where it is.
- **Clear Bets takes down what a dealer would let you.** Everything comes
  off on request except the two contract bets — the pass line once a point
  is on, and come bets that have travelled to their number. Those ride
  until they win or lose. Odds, place bets, the props and the whole don't
  side are always yours to pick up between rolls.
- **Walking away costs the contracts.** Leaving the table hands back every
  removable bet, but the pass line and travelled come bets can't come down
  and the game doesn't wait for someone who left — they are forfeited.
  That is the price of walking out mid-hand; make the point or seven out
  first if you want to leave whole.
- Place and odds payouts **round down to the dollar**, as a dealer does. Bet
  the 6 and 8 in multiples of $6 and the rest in multiples of $5 for the
  full price.

| Group | Bets | Pays | Edge |
| --- | --- | --- | --- |
| Line | Pass | 1:1 | 1.41% |
| | Don't Pass (bar 12) | 1:1 | 1.36% |
| Odds | behind pass, don't pass, and every come point | true price: 2:1 on 4/10, 3:2 on 5/9, 6:5 on 6/8, laid inverse for the don't | none |
| Come | Come | 1:1 | 1.41% |
| | Don't Come (bar 12) | 1:1 | 1.36% |
| Place | 4, 10 | 9:5 | 6.67% |
| | 5, 9 | 7:5 | 4.00% |
| | 6, 8 | 7:6 | 1.52% |
| Field | 2, 3, 4, 9, 10, 11, 12 | 1:1, the 2 pays 2:1 and the 12 pays 3:1 | 2.78% |
| Big | Big 6, Big 8 | 1:1 | 9.09% |
| Hardways | 4, 10 | 7:1 | 11.1% |
| | 6, 8 | 9:1 | 9.09% |
| Props | Any 7 | 4:1 | 16.7% |
| | Any Craps | 7:1 | 11.1% |
| | 2, 12 | 30:1 | 13.9% |
| | 3, 11 | 15:1 | 11.1% |
| | Horn (quartered over 2, 3, 11, 12) | winning quarter pays its own odds | 12.5% |
| | C & E (halved between any craps and the yo) | winning half pays its own odds | 11.1% |

#### Come bets

A come bet is the pass line one roll out of step. Put it on the COME bar
while a point is on and it wins on 7 or 11, loses to craps, and otherwise
**travels to the number rolled** and waits there for that number to repeat.

The moment a come or don't come bet lands on a number, its box grows a
gold **odds spot** — *ODDS 3x/4x/5x* with the true price for a come bet,
*LAY ODDS* for a don't come. Tap it (or the bet itself) to put chips
behind the bet at the Vegas 3-4-5x limits: taken odds pay 2:1 on the 4
and 10, 3:2 on the 5 and 9, 6:5 on the 6 and 8, and lays pay the same
odds the other way up.

Several can be live at once, each on its own number with its own odds, and
one seven kills the lot. Don't come is the mirror: it travels the same way,
wins on the seven, and bars the twelve.

Come chips can't be placed straight onto a number — they have to win their
way over from the bar, which is why tapping a number's COME cell takes odds
rather than placing a new bet.

#### Systems Lab (pack)

The roulette lab's flowchart builder, for the dice, playing the table's own
rules. A craps layout means *keep these bets up*: line bets go down on a
come-out and come bets once a point is on, each bet is topped back up before
the roll, a dropped bet comes down unless it's a contract, and odds go behind
the line or every come point at the multiple asked for, within the 3-4-5x
caps. Rules can also react to seven-outs, points set and made, naturals,
craps, hard ways and any total, and test the point and the number of come
bets working; actions add odds, press and regress. Presets: pass line with
max odds, don't pass laying odds, Iron Cross, 3-Point Molly, place 6 and 8
with a press, and Martingale on the pass line. Each result is set against
each settled bet's own house edge. The table's lab button won't leave a
contract bet stranded mid-hand — finish the hand first.

### Baccarat

Punto Banco: eight decks, no decisions. Back the **Player**, the **Banker**
or a **Tie**, plus either pair side bet, and the tableau does the rest.

- Aces count one, pips at face value, tens and courts nothing; a hand's
  total is its cards **modulo ten**, so 7 + 8 is 5.
- An **8 or 9 on either side is a natural** and ends the hand where it
  stands.
- The player draws on 0-5 and stands on 6-7.
- The banker follows the fixed tableau: 0-2 always draws, 3 unless the
  player's third card was an 8, 4 on a player third of 2-7, 5 on 4-7, 6 on
  6-7, and 7 stands. With the player standing it simply draws on 0-5.

| Bet | Pays |
| --- | --- |
| Player | 1:1 |
| Banker | 1:1 **less 5% commission** |
| Tie | 8:1 (Player and Banker push) |
| Player Pair / Banker Pair | 11:1 |

Commission is taken out of the winnings and **rounded to the nearest
dollar**, and the result line always names it, so a $100 banker win reads as
+$95 with the $5 accounted for rather than silently missing.

Pairs are by **rank, not value** — a king and a ten both count zero but are
not a pair.

#### Coin Flip (free)

Unlock it in Extras and a **Coin Flip** button appears on the rail. The hand
is still dealt from the shoe and settled by the tableau, so the odds and the
payouts are exactly the same — but all the table shows is a coin: heads for
the banker, tails for the player, on its edge for a tie. Baccarat has no
decisions; this is what it is underneath. The pair bets need cards, so they
leave the table while it's on.

The shoe reshuffles at the same 25% cut card as blackjack, and the card
count is shown under the table.

## Project layout

| Path | Purpose |
| --- | --- |
| `scripts/save_data.gd` | Everything saved between launches (`SaveData` autoload) |
| `scripts/bank.gd` | Shared bankroll autoload (`Bank`), saved through `SaveData` |
| `scripts/store.gd` | What the player owns (`Store` autoload): Google Play Billing, the Steam edition with everything included, or every pack unlocked where there's no store |
| `scripts/window_mode.gd` | Fullscreen on desktop (`WindowMode` autoload): F11 / Alt+Enter, remembered |
| `scripts/main_menu.gd` + `scenes/main_menu.tscn` | Lobby, with the play-money notice and About box |
| `scripts/extras.gd` + `scenes/extras.tscn` | Extras: packs, free unlocks and the tip jar |
| `scripts/modal.gd`, `scripts/locked_pack.gd` | Shared overlay panel, and the cover a locked pack shows |
| `scripts/blackjack.gd` + `scenes/blackjack.tscn` | Blackjack table and trainer panel |
| `scripts/blackjack_shoe.gd`, `scripts/card_view.gd` | The shoe and its Hi-Lo count, and how a card is drawn — shared with the trainers |
| `scripts/blackjack_strategy.gd` | Hi-Lo values, basic strategy, and count index plays |
| `scripts/strategy_chart.gd` | The strategy charts, generated from `BlackjackStrategy` |
| `scripts/strategy_quiz.gd`, `scripts/strategy_drill.gd` + `scenes/strategy_drill.tscn` | Strategy Trainer: its questions, and its screen |
| `scripts/blackjack_round_sim.gd`, `scripts/count_drill.gd` + `scenes/count_drill.tscn` | Counting Trainer: a table of basic-strategy players, and its screen |
| `scripts/roulette.gd` + `scenes/roulette.tscn` | Roulette table |
| `scripts/roulette_bets.gd` | What every roulette bet covers and pays — the table and the lab both read it |
| `scripts/roulette_wheel.gd` | Custom-drawn spinning wheel |
| `scripts/craps.gd` + `scenes/craps.tscn` | Craps table and rail |
| `scripts/craps_engine.gd` | The craps rules: every bet's settlement, shared by the table and the lab |
| `scripts/craps_table.gd` | The felt: every betting area's geometry, and the painting of it |
| `scripts/craps_die.gd` | Die face drawn from pips, shared by the dice and the prop box |
| `scripts/poly_button.gd` | Button whose clickable area is a polygon, not its rectangle |
| `scripts/baccarat.gd` + `scenes/baccarat.tscn` | Baccarat table and drawing tableau, with Coin Flip mode |
| `scripts/coin.gd` | The coin Coin Flip shows |
| `scripts/system_model.gd`, `scripts/system_presets.gd` | Systems Lab: the shape of a system, and the famous ones |
| `scripts/system_runner.gd`, `scripts/roulette_sim.gd`, `scripts/craps_sim.gd` | Playing a system: the rules interpreter, and each game's simulated table |
| `scripts/system_lab.gd` + `scenes/system_lab.tscn` | The lab's screen, shared by both games |
| `scripts/rule_editor.gd`, `scripts/position_picker.gd`, `scripts/flowchart_view.gd`, `scripts/lab_chart.gd` | The lab's editors, bet picker, flowchart and results chart |
| `scripts/casino_ui.gd` | Shared button and panel styling |
| `scripts/bet_board.gd` | Shared chip-placement board used by roulette, craps and baccarat |
| `scripts/safe_area.gd` | Notch/cutout-aware margin container |
| `tests/run_all.gd` + `tests/*_rules.gd` | Rule suites, run by CI |
| `export_presets.cfg` | Linux, Windows, Android (debug APK), Android Play (signed App Bundle), Steam Linux and Steam Windows presets used by CI |
| `PRIVACY.md`, `docs/PLAY_RELEASE.md`, `docs/STEAM_RELEASE.md` | The privacy policy, and how to publish on Google Play and on Steam |
| `.github/workflows/build.yml` | Check, export, and release pipeline |
| `.github/actions/setup-godot/` | Composite action that installs Godot + templates |

All UI is built in code from plain Control nodes, so there are no binary
assets — the whole game is readable GDScript.

## The rule suites

`tests/run_all.tscn` drives the real scenes rather than a copy of the rules,
so a suite passing means the shipped game behaves. CI runs it on every push;
locally it is one command:

```bash
godot --headless --path . res://tests/run_all.tscn
```

| Suite | What it pins down |
| --- | --- |
| `save_rules` | The bankroll, notice, scores and fullscreen choice survive a restart, About names the right store, and the suites never touch a real save |
| `layout_fits` | Every scene fits the 1280x720 design viewport |
| `blackjack_rules` | Shoe composition, the Hi-Lo count against the undealt remainder, both strategy charts and their indices, split stakes, split aces, insurance |
| `roulette_rules` | Wheel order and colours, the board covering 1-36 once, payouts, and every way a repeat-until-win run can stop |
| `craps_rules` | The 2d6 distribution, every payout on the table, the 3-4-5x caps, come bets travelling and dying, what a seven-out takes, which winners stay up, what Clear Bets may and may not remove, and that every hit-zone on the felt matches the paint |
| `baccarat_rules` | All 80 cells of the banker tableau, naturals, pair detection, and commission arithmetic |
| `store_rules` | Packs start locked and unlock when bought; pending payments unlock nothing; purchases are acknowledged, tips consumed, refunds taken back; restore; free unlocks; the Steam edition includes every pack, sells nothing and shows no tip jar |
| `baccarat_coin_rules` | Coin Flip settles every hand exactly as card mode does |
| `blackjack_trainer_rules` | The charts against the published chart, the quiz against `BlackjackStrategy` over thousands of hands, and the drill's scoring, corrections and Blitz |
| `count_trainer_rules` | Table order, the hole card counted only when it turns over, 1,500 rounds of basic-strategy seats against an S17 dealer, and the drill's checks and timer |
| `systems_rules` | The lab pays every bet as the table does; rules, groups, patterns, steps, stops and the table cap; flat red converges on the 2.7% edge |
| `system_lab_rules` | Every kind of condition and action can be built in the editor; runs, saving and sharing from the screen |
| `craps_lab_rules` | Craps bets go down only in season, contracts stay, odds respect the caps, events report correctly, and the presets play as described |

Three of those are worth calling out. The craps suite rolls the dice 180,000
times and checks the histogram against the real 2d6 distribution, because
`randi() % 11 + 2` is uniform over 2-12, looks entirely reasonable, and
would quietly make it a different game. It also checks all 51 hit-zones on
the felt: that each bet has an area, no two areas overlap, and a click on
each chip spot lands on the bet the paint says it should — the felt is one
painted picture with polygons layered over it, so a wrong polygon still
screenshots perfectly. That check caught the pass line's own chip spot
sitting inside its odds zone, which would have put line chips on the odds
spot and turned taps meant for the line into odds bets.

The baccarat suite checks the banker tableau exhaustively against an
independently restated copy of the published table, because the tableau *is*
the game and one wrong cell would be invisible in play.

## Building locally

Godot cross-compiles Windows binaries from Linux, so one Godot install
produces both. With the editor and matching export templates installed:

```bash
godot --headless --import --path .
godot --headless --path . --export-release "Linux"   "$PWD/build/Casino.x86_64"
godot --headless --path . --export-release "Windows" "$PWD/build/Casino.exe"
```

`--export-release` takes the **preset name** from `export_presets.cfg`
(`Linux` / `Windows`), not the platform name. The Steam edition is the same
command with `"Steam Linux"` or `"Steam Windows"`.

## Continuous integration

`.github/workflows/build.yml` runs on every push, pull request, and manually
via *Run workflow*:

1. **Check** — imports the project, boots it headless, and runs the rule
   suites, failing the build on any parse error, runtime error, or broken
   rule — including a script error inside a suite, which could otherwise skip
   checks without failing one.
2. **Export** — builds Linux and Windows, and the Steam edition of each, in
   parallel and uploads each as an artifact. The Steam artifacts hold only
   the game, ready to upload as depots.
3. **Export Android** — builds a debug-signed APK. Godot reads the SDK
   location from Editor Settings rather than the environment, so this job
   generates that file with `--editor --quit` and rewrites the two path keys
   before exporting. It then checks the APK really is one, by looking for
   `AndroidManifest.xml` and `classes.dex` inside it.
4. **Export Android (Play)** — on a `v*` tag (or by hand), builds the signed
   App Bundle for the Play Store with Google Play Billing; see
   [docs/PLAY_RELEASE.md](docs/PLAY_RELEASE.md) for the keystore secrets it
   needs.
5. **Publish release** — on a `v*` tag, zips the free builds (Linux, Windows
   and the debug APK) and attaches them to a GitHub release. The Play bundle
   and the Steam builds go to their stores, never here.

Godot itself exits `0` even when scripts fail to parse, so
`.github/scripts/assert-no-godot-errors.sh` scans the logs instead. It ignores
the Vulkan and ALSA fallback errors that every GPU-less CI runner produces,
while still failing on script and resource errors.

To move to a new engine version, change `GODOT_VERSION` at the top of the
workflow — the editor and export templates are downloaded and cached together
under that key.
