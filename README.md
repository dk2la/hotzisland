# HotzIsland

**Turn your MacBook notch into an instrument.**

A Dynamic Island for macOS — a living notch with one-tap workspace playbooks, media controls, calendar, system meters, a file shelf, clipboard history and a pomodoro timer. Styled like studio hardware: matte black, hairlines, mono readouts, a single accent color. Open source, built with SwiftUI.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-3FFF00)

<!-- TODO: hero screenshot / GIF — docs/hero.gif (expanded island, Play tab) -->

## What it does

Hover the notch and it expands into a panel with seven channels:

| Channel | What's inside |
| --- | --- |
| **Play** | Playbooks — one tap opens your set of apps, politely quits the rest, switches Focus via Shortcuts and starts a timer. `work`, `film`, `clear` — you define them. |
| **Media** | Now playing with artwork, segmented progress and tape-deck transport keys. Spotify and Apple Music, switchable sources. |
| **Cal** | Today's agenda as data registers. The next meeting gets a `T−12m · join` countdown — click to jump into Zoom/Meet. Month grid, multiple accounts (iCloud, Google, Exchange) out of the box. |
| **Sys** | CPU · MEM · NET · PWR instrument cells with segment meters, a CPU history strip and a volume register. |
| **Shelf** | Drag files onto the notch — they wait there, drag them out when needed. Links only, originals stay put. |
| **Clip** | Clipboard history. In-memory only; password-manager entries are never recorded. |
| **Timer** | Pomodoro presets, wall-clock accurate, big mono countdown. Runs in the compact island while you work. |

While the island is closed it stays quiet: a small indicator with a mono readout for a playing track or a running timer, and short live events for charging, headphones and volume. **The norm is darkness** — light means something is happening.

<!-- TODO: screenshots row — docs/media.png · docs/sys.png · docs/playbooks.png -->

## Playbooks

The feature everything else orbits around. A playbook is a saved workspace state:

```json
{
  "name": "work",
  "openBundleIDs": ["com.google.Chrome", "com.jetbrains.pycharm", "md.obsidian"],
  "closeOthers": true,
  "shortcutName": "Work Focus",
  "timerMinutes": 25
}
```

One tap: apps you need open, everything else politely quits (⌘Q semantics — unsaved work is always asked about, never killed), a Shortcuts shortcut fires (that's how Focus modes are switched — and anything else Shortcuts can do), the pomodoro starts. Create and edit playbooks in Settings; they live as JSON in `~/Library/Application Support/HotzIsland/`.

## Install

No releases yet — build from source (two commands, ~1 minute):

```bash
brew install xcodegen
git clone https://github.com/dk2la/hotzisland.git && cd hotzisland
xcodegen && xcodebuild -project HotzIsland.xcodeproj -scheme HotzIsland -configuration Release build
```

Requirements: **macOS 14+**, Xcode 16+. A physical notch is not required — on other Macs the island draws its own capsule at the top of the screen.

## Permissions

Everything is optional — without access a module hides instead of nagging:

| Permission | Used for | Asked when |
| --- | --- | --- |
| Calendars | The Cal channel | First launch |
| Automation (Spotify, Music) | Reading and controlling playback | First time media is polled |
| — | Everything else works without permissions | |

Nothing leaves your Mac. No analytics, no network calls except artwork downloads from Spotify's CDN.

## Honest limitations

- **Browser media (YouTube etc.) can't be shown or controlled.** Apple locked the private MediaRemote framework to entitled apps in macOS 15.4+ — third-party apps can no longer read the system's now-playing. Media works through AppleScript, which only Spotify and Apple Music provide.
- Focus modes have no public API — playbooks switch them through a Shortcuts shortcut you create once.
- The app is unsigned for now: macOS will warn on first launch of a downloaded build. Building from source avoids this entirely.

## Roadmap

- Global hotkeys (open/close the island from the keyboard)
- LLM assistant — bring your own Claude/OpenAI key, drive playbooks and timers by chat or voice
- A tamagotchi living in the notch (yes)
- User-defined custom panels from instrument blocks
- Switchable design systems

## Development

The Xcode project is generated — `*.xcodeproj` is not committed:

```bash
xcodegen && open HotzIsland.xcodeproj
```

Layout: `Sources/Core` (notch window, state machine, design tokens), `Sources/Modules/<Channel>`, `Sources/Services` (EventKit, CoreAudio, IOKit, AppleScript bridges), `Sources/Settings`. UI is SwiftUI; the window mechanics are AppKit. Swift 6 strict concurrency throughout.

## Credits

Inspired by [Boring Notch](https://github.com/TheBoredTeam/boring.notch), [Atoll](https://github.com/Ebullioscopic/Atoll) and NotchNook. No code was taken from GPL projects — approaches only.

## License

[MIT](LICENSE) © Danila Kozlov
