# Releasing on Google Play

How Casino makes money, what it will never do, and the steps to get a
build into the Play Store.

## The deal with players

Everything that was free stays free. Money comes from optional one-time
packs and a tip jar:

| Product | ID | Type | Suggested price |
| --- | --- | --- | --- |
| Strategy Trainer | `strategy_trainer` | one-time | $2.99 |
| Card Counting Trainer | `count_trainer` | one-time | $2.99 |
| Roulette Systems Lab | `roulette_lab` | one-time | $3.99 |
| Craps Systems Lab | `craps_lab` | one-time | $3.99 |
| Small / medium / large tip | `tip_small` / `tip_medium` / `tip_large` | consumable | $1.99 / $4.99 / $9.99 |

The strategy charts and baccarat's Coin Flip are free and never touch the
store. The suggested prices only show in the test store; on a phone every
price is Google Play's localized one.

The rules the code is built around, and that any future work should keep:

- **No chips for sale, ever.** Chips are free, unlimited and worthless. Selling
  them is the social-casino model, and in Washington state it got bought chips
  treated as a "thing of value" in court (*Kater v. Churchill Downs*, 9th Cir.
  2018), with settlements in the hundreds of millions.
- **Nothing free moves behind a paywall.** Only new features are sold.
- **The free game always shows the count, the strategy hints, the charts and
  the craps house edges.** The labs always show what the edge predicts beside
  what actually happened.
- **No ads, no analytics, no tracking.** So the data-safety answer is "no
  data collected", and there's no consent banner.
- **No pressure:** no loot boxes, no timers on offers, no fake discounts, no
  streak rewards, no push notifications, no pop-ups when chips run out, no
  subscription. Locked features say where they live and leave it there.

## One-time setup

1. **A Play developer account** ($25). A *personal* account created after
   November 2023 has to run a closed test with at least 12 testers for 14
   days before it can publish to production. An organization account doesn't.
   Check the Play Console for the current rule.
2. **Create the app** with package name `systems.fu.casino`, and turn on
   **Play App Signing**. Google keeps the key that signs what players
   install. You keep an *upload key* that proves a bundle came from you.
3. **Make the upload key** and keep it somewhere safe:

   ```bash
   keytool -genkeypair -v -keystore upload.keystore -alias upload \
     -keyalg RSA -keysize 2048 -validity 10000
   ```

4. **Give CI the key** as three repository secrets (Settings → Secrets and
   variables → Actions):

   | Secret | Value |
   | --- | --- |
   | `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload.keystore` |
   | `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
   | `ANDROID_KEY_ALIAS` | `upload` (or whatever alias you chose) |

5. **Create the in-app products** in the Play Console under *Monetize →
   Products → In-app products*, with the IDs in the table above. The four
   packs are ordinary one-time products. The tips are one-time products too:
   the game consumes them, so they can be bought again. Use the bullet points
   from the Extras screen as each pack's description.

## The store listing

- **Content rating (IARC questionnaire):** answer *yes* to simulated
  gambling. Expect an adult rating. Apple rates frequent simulated gambling
  18+, and Australia rates it R18+ in both stores.
- **Target audience:** 18 and over only. Don't opt into *Designed for
  Families*.
- **Ads:** none.
- **Data safety:** no data collected or shared. Purchases go through Google
  Play itself.
- **Privacy policy:** `PRIVACY.md` at the root of this repository. If the
  repository is private, publish that text somewhere public (GitHub Pages
  works) and link to that copy instead. Add a contact email to it too; the
  listing needs one.
- **Store icon:** a 512×512 PNG. ImageMagick can make one from the game icon:
  `convert -background none -density 384 icon.svg -resize 512x512 store-icon.png`.
- **Pitch:** lead with the honest angle — the casino that shows you the house
  edge, with trainers that teach basic strategy and counting, and labs that
  test betting systems properly.

## Building a release

Push a version tag:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

The **Export Android (Play)** job then:

1. checks the upload-key secrets are set;
2. installs Android platform 35 and build-tools 35.0.0, which the Godot 4.5.1
   Gradle template compiles against;
3. downloads the Google Play Billing plugin (`GodotGooglePlayBilling` 3.3.0,
   the release built for this Godot version) into `addons/`, and enables it
   for this build only — the committed project never loads it, so the
   desktop builds and the everyday debug APK don't depend on it;
4. stamps `version/code` from the run number (Play rejects a reused one) and
   `version/name` from the tag;
5. exports the **Android Play** preset as a signed App Bundle, checks it's a
   real bundle, and uploads it as the `casino-android-play` artifact.

Download that artifact and upload `Casino.aab` to a Play Console track.
*Run workflow* on the Build workflow makes the same bundle without a tag,
versioned `0.0.<run number>`.

### Target API level

Since 31 August 2026, Play only accepts new apps and updates that target
Android 16 (API 36). The Android Play preset sets
`gradle_build/target_sdk="36"`. Godot 4.5.1's Gradle template still compiles
against API 35 — that builds, since the template doesn't fail on lint —
but when the project moves to a Godot whose template targets 36 or higher by
itself, the override can go.

### Building the bundle by hand

From the editor: install the billing plugin from the Asset Library (or the
release zip into `addons/GodotGooglePlayBilling/`), enable it under *Project →
Project Settings → Plugins*, run *Project → Install Android Build Template*,
then export the **Android Play** preset with your upload keystore filled in.
Keep the plugin out of commits, or the desktop exports will try to load it.

## Testing purchases

- Upload a bundle to the **internal testing** track and add your Google
  account under *Settings → License testing*. Testers buy with test cards and
  aren't charged.
- Things to try: buy each pack; reinstall and tap **Restore Purchases**;
  refund a pack in the Play Console and check it locks again on the next
  launch; pay with the "slow test card" and check a pending payment unlocks
  nothing until it clears; tip twice in a row.
- Builds without the `play_store` feature (desktop, the debug APK) have no
  store to buy from, so they unlock every pack and leave the free ones as a
  tap. Change `Store._ready` if desktop builds are ever sold.

## Later: the App Store

Not built yet. It needs an iOS export preset, a macOS runner in CI (Godot's
iOS export needs Xcode), the Apple Developer Program ($99 a year) and a
StoreKit plugin; `Store` would gain a third backend beside Google Play's. The
age rating there is 18+ for frequent simulated gambling.
