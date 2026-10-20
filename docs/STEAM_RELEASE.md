# Releasing on Steam

How the Steam edition differs from the other builds, and the steps to get it
onto the Steam store.

## The deal

On Steam, Casino is sold once, at one price, with everything included:

- every pack (both trainers and both systems labs), plus the free unlocks,
  which are still a tap;
- no DLC, no microtransactions and no tip jar — a game someone has already
  paid for doesn't ask for more;
- the same rules as everywhere else: no chips for sale, ever; the free game
  always shows the count, the strategy hints and the house edges; no ads,
  analytics or tracking.

The free builds stay free. Casino is open source, and the Linux, Windows and
Android builds on GitHub carry on with every pack unlocked. Say so on the
store page rather than hoping nobody notices — for example: *"Casino is open
source and free to build yourself. The Steam edition is the easy way to get
it: installed and updated by Steam, with your bankroll, scores and systems
synced through Steam Cloud — and buying it supports the developer."*

## What makes a build the Steam edition

The **Steam Linux** and **Steam Windows** export presets carry the custom
feature `steam`. With it:

| | Steam edition | Other desktop builds |
| --- | --- | --- |
| Packs | all included | all unlocked |
| Tip jar | hidden | shown (disabled) |
| About box | "Steam handles the purchase…" | "Nothing is sold in this build." |
| First launch | fullscreen | windowed |

F11 or Alt+Enter switches fullscreen in every desktop build, and the choice
is remembered. `Store._ready` picks the backend; `Store.all_included()`,
`sells_tips()` and `privacy_note()` carry the differences.

The game doesn't use the Steamworks SDK. A paid game with no achievements
doesn't need it, and Steam Cloud works without it, so the Steam edition still
never connects to the internet and collects nothing.

## One-time setup

1. **Join Steamworks** at partner.steamgames.com. It asks for identity, bank
   and tax details.
2. **Pay the Steam Direct fee** ($100 per app). Valve pays it back once the
   game has made $1,000 in adjusted gross revenue. After paying, there's a
   30-day wait before the game can be released.
3. **Create the depots** under *SteamPipe → Depots*: one for Windows and one
   for Linux. Note each depot ID.
4. **Set the launch options** under *Installation → General*:

   | Executable | Operating system |
   | --- | --- |
   | `Casino.exe` | Windows |
   | `Casino.x86_64` | Linux + SteamOS |

   For Linux, choose **Steam Linux Runtime 3.0 (sniper)** as the runtime, so
   the game runs in the same container on every distribution and on the Deck.
5. **Turn on Steam Cloud (Auto-Cloud)** under *Application → Steam Cloud*:
   - Byte quota per user: 10 MB. Number of files per user: 10.
   - Root path: **WinAppDataRoaming**, subdirectory `Godot/app_userdata/Casino`,
     pattern `save.cfg`, OS Windows.
   - Root override for Linux: **LinuxXdgDataHome**, subdirectory
     `godot/app_userdata/Casino`.

   Those are Godot 4's default `user://` folders for a project named
   `Casino`. **Never rename the project** (`application/config/name` in
   `project.godot`): the save folder would move, and every player's
   bankroll, scores and systems would be left behind.
6. **Set a default controller layout** under *Application → Steam Input*.
   Casino has no gamepad controls, so pick a mouse-style template, where the
   right trackpad moves the pointer and the right trigger clicks. The Deck's
   touchscreen works as it is.

## The store page

The page goes through Valve's review (a few business days), and has to be
public as **Coming Soon** for at least two weeks before launch. Start it
early, because wishlists collect while it's up.

- **Title.** "Casino" alone is impossible to find in search. Use a
  distinctive store title such as *Casino: Honest Odds*. That's only the
  store's name for it; the project's own name must stay `Casino` (see
  step 5).
- **Description.** Lead with the honest angle: the casino that shows you the
  house edge, with trainers that teach basic strategy and card counting, and
  labs that test betting systems against thousands of simulated sessions.
- **Content survey.** Declare the simulated gambling under general mature
  content, in plain words: casino games played with free play money only; no
  currency is sold; there are no prizes and no cash-out. Mark it for adults.
- **AI-generated content disclosure.** Answer it honestly, against the
  wording Valve uses when you fill it in.
- **Languages.** English (interface).
- **System requirements.**
  - OS: Windows 10 64-bit, or SteamOS / 64-bit Linux.
  - Graphics: Vulkan, Direct3D 12 or OpenGL 3.3. The game uses Godot's
    Forward+ renderer and falls back down that list on its own.
  - Storage: under 200 MB.

### Art

Valve enlarged most capsules in August 2024 and no longer takes the old
sizes, so check every one against Steamworks' asset page before exporting.

| Asset | Size |
| --- | --- |
| Header capsule | 920×430 |
| Small capsule | 462×174 |
| Main capsule | 1232×706 |
| Vertical capsule | 748×896 |
| Library capsule | 600×900 |
| Library header | 920×430 |
| Library hero | 3840×1240 |
| Library logo | 1280 wide and/or 720 tall, transparent |
| Screenshots | at least 5, 1920×1080 |

Capsules should show the game's name and art, not review quotes, discount
badges or awards. Screenshots should be the real game: capture them at
1920×1080 with the window fullscreen.

A short trailer helps, but it's optional.

### Price

Suggested: **$4.99**, with Steam's recommended regional prices. On Google
Play the four packs together cost $13.96, so the Steam edition is the cheaper
way to get everything, as befits paying up front.

A launch discount is fine as long as it's a real one. Never inflate the base
price to make a discount look bigger.

## Building and uploading

The **Export** job in CI builds the Steam presets on every push, as the
artifacts `casino-steam-linux` and `casino-steam-windows`. They hold only the
game — no README — and never go into the GitHub release.

For a release, push a version tag, open its run, and download both
artifacts. Then upload from Linux or macOS (or WSL), which keeps the Linux
binary executable:

```
steam/
  app_build.vdf
  content/
    windows/Casino.exe
    linux/Casino.x86_64
```

```bash
chmod +x steam/content/linux/Casino.x86_64   # GitHub artifacts drop the bit
```

`steam/app_build.vdf` (put in your app and depot IDs):

```
"AppBuild"
{
	"AppID" "YOUR_APP_ID"
	"Desc" "Casino v1.0.0"
	"ContentRoot" "./content/"
	"BuildOutput" "./output/"
	"Depots"
	{
		"YOUR_WINDOWS_DEPOT_ID"
		{
			"FileMapping"
			{
				"LocalPath" "windows/*"
				"DepotPath" "."
				"Recursive" "1"
			}
		}
		"YOUR_LINUX_DEPOT_ID"
		{
			"FileMapping"
			{
				"LocalPath" "linux/*"
				"DepotPath" "."
				"Recursive" "1"
			}
		}
	}
}
```

Upload it with [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD):

```bash
steamcmd +login YOUR_STEAM_LOGIN +run_app_build "$PWD/steam/app_build.vdf" +quit
```

The first login asks for a Steam Guard code. The build then shows up under
*SteamPipe → Builds*. Set it live on the default branch there, or on a beta
branch first if you want to try it from the Steam client.

Keep the `steam/` folder out of the repository; it holds builds and your
IDs.

Uploading from CI is possible later, for example with `game-ci/steam-deploy`.
It needs a separate Steam account with build rights, and that account's
`config.vdf` stored as a secret so Steam Guard doesn't stop it. That's worth
setting up only once releases are frequent.

## Before launch

- **Steam Cloud.** Play on one machine, quit, and check `save.cfg` appears
  under the account's Steam Cloud page. Then launch on a second machine (or
  on Linux after Windows) and check the bankroll followed.
- **Steam Deck.**
  - The Deck's 1280×800 screen suits the 1280×720 design size; the `expand`
    stretch fills the extra height rather than letterboxing.
  - The touchscreen and the right trackpad drive everything.
  - Request a compatibility review in Steamworks. Without gamepad controls,
    expect **Playable** rather than **Verified**.
- **Both depots.** Install from Steam on Windows and on Linux. The game
  should start fullscreen, F11 should switch to a window and back, and Extras
  should open every pack with no tip jar.
- **Build review.** Valve also reviews the build before launch; allow a few
  business days.

## Updates

Tag a release, download the two Steam artifacts from its run, upload with
the same `app_build.vdf` (change `Desc`), and set the new build live. Steam
updates every copy automatically, and Steam Cloud carries the save across.
