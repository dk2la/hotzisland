# HotzIsland V3 — visionOS design system

Source of truth for the V3 look. Figma: "HotzIsland Redesign" → page **V3 · visionOS**.
Code home: `Sources/Core/Theme.swift`, `Sources/Core/GlassControls.swift`.

## Material

| Surface | Recipe |
|---|---|
| Window glass (light) | `.ultraThinMaterial` + white 9% tint + 1px stroke white 20% |
| Window glass (dark) | `.ultraThinMaterial` + black 52% tint + 1px stroke white 14% |
| Raised glass | white 12% (buttons, chips, fields) |
| Card | white 6% (rows, tiles) |
| Selected | solid white 96% + dark glyph `#1C1D21` — the only accent |
| Critical | `#FF454A` — badges and critical meters only |

The island housing stays hardware black; the island sheet is always dark
glass. The widget follows `Settings → Материал виджета` (Light / Dark / Auto).

## Shape

- Window radius **28** (continuous), ornament capsule radius **28**
- Cards/rows **16**, controls **14**, pills/circles — capsule
- Ornament: thickness **56**, cells **44** (circular), spacing 8, edge inset 8
- Panel inset **16**

## Type — SF Pro

| Role | Spec |
|---|---|
| Title | 15 Semibold |
| Headline | 13 Semibold |
| Body | 13 Regular |
| Sub | 12 Regular · 50–72% |
| Caption | 11 Medium · tracked, 38–50% |
| Readouts | monospaced digits (`Theme.mono`); big countdown 44 Semibold |

White vibrancy ramp: 100 / 72 / 50 / 38 / 32%. Data never animates — values jump.

## Modules

Enabled by default (replaceable): Playbooks, Calendar, Email*, Clipboard, Notes*, Chats*.
Optional (Settings → Модули): Music, Timer, Shelf, System.
`*` — coming soon: `NotchTab.comingSoon`, excluded from the default enabled set,
render `ComingSoonModuleView` until their services land.

## Motion (from V2 spec)

- Panel open 220ms `cubic-bezier(0.23,1,0.32,1)` ≈ `.spring(response:0.28,dampingFraction:0.9)`; origin = rail edge
- Panel close 160ms — exit is always faster than enter
- Island expand `.spring(duration:0.45,bounce:0.15)` — interruptible
- Press: scale 0.96–0.97, 120ms (`PressableStyle`)
- Hotkey toggles and running readouts never animate

## Interactivity target

Every module screen acts in place: type a note, reply to email, join a call,
run a playbook — nothing bounces the user to an external app.
