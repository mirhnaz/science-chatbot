# Design

The shared design for Curio. The iPad/iOS app implements it first
(`ios/Curio/ContentView.swift`), following Apple's Human Interface
Guidelines for Liquid Glass (iOS/iPadOS 26 and later). The web page now
uses the same curiosity column in plain TypeScript ([FRONTEND.md](FRONTEND.md)).

> **Superseded where they conflict** by the 2026-09 redesign (Home, Trail,
> Trail complete): [design/redesign-2026-09/curio-redesign-handoff.md](design/redesign-2026-09/curio-redesign-handoff.md).
> It applies to iPhone and iPad. Tokens below are reconciled with it.

## The curiosity column (current iPad build)

[design/curiosity-column.png](design/curiosity-column.png) (source:
[design/curiosity-column.html](design/curiosity-column.html)) replaces the
Ideas sidebar with one column where every "what next?" choice sits near the
question box. Built in `ios/Curio/ContentView.swift`:

- Fresh sessions centre the question box with four starter ideas; on the first
  question the box moves to the bottom.
- A **trail** stacks the questions and answers of one topic. Only the latest
  step is open; earlier steps fold to their question, a short preview, and the
  follow-up the child chose.
- **Dive deeper** (the follow-ups) sits under the latest answer. **New spark** (starter chips, 🎲 "New sparks", and "✎ Ask your own") sits
  above the question box and starts a new trail. On the fresh screen the same
  starters are titled **Sparks** ("Pick one to start exploring"). Typing in the box continues the trail.
- Tapping any suggested question asks it at once; long-press edits first.
- Each trail becomes one History entry later, so there is no "New chat"
  button; until then, a replaced trail can be restored with Undo.
- Read aloud moves onto each answer; the toolbar keeps only Settings.
- Phones (iPhone, narrow web): the question box sits at the bottom from the
  start, with the hero and compact Sparks scrolling above; iPad and wide
  windows centre it.
- The question box is a filled field with a thin outline (not see-through
  glass, which vanished on a light background); the send button keeps glass.
- The dock is a `safeAreaBar`, so the trail fades and blurs beneath it like
  under the toolbar (web: a gradient mask or `backdrop-filter` behind the
  sticky dock).

### Future: trails as a map of a child's interests

Trails are meant to grow into more than history. After a child has used the
app for a considerable time, their saved trails show **which topics they return
to most, which trails they follow deepest, and what they are curious about**.
Ideas to build on later (none are implemented or scheduled):

- A "My curiosity" view: most frequent topics and trails, and the longest
  (deepest) trails.
- Suggesting starters from the child's own interests, not only at random.
- Continuing an old trail from where it stopped.
- A parent or teacher summary.

This needs saved history, so it depends on login/history and a decision about
what is stored, for how long, and who can see it. Children's data must stay
private and minimal; decide retention and consent before building it.

The sections below describe the earlier sidebar build, now superseded on
iPad; the principles and tokens still apply to both.

## Principles

- **Two layers.** Content (ideas, the answer) sits on plain backgrounds.
  Controls (toolbar buttons, the question box) float above it on glass, and
  content scrolls underneath. Glass is never used for content cards.
- **Native, not a web page.** Hierarchy comes from type sizes and spacing, not
  outlines or small spaced capitals. No borders around every element.
- **One accent.** Purple is the only brand colour; everything else uses the
  platform's text and background colours so Dark Mode and contrast settings
  work.
- **For 10–13 year olds.** No technical wording on the main screen (engine
  names). Each answer shows a small "Answered in N seconds" to spot delays
  ("· on this iPad" when answered offline). Large, readable answer text.

## Layout

```text
┌─────────────┬───────────────────────────────────────────┐
│ Ideas   🎲  │          Curio        🔊   ⚙︎   │  glass toolbar
│─────────────│             (Thinking… / Offline mode)    │
│ Sparks      │  Why does a straw look bent?  (title)     │
│ 🌈 Light    │  Answer text, max 680 pt/px wide          │
│ ⚡ Electric…│                                           │
│ …           │  Keep exploring                           │
│             │   Follow-up one                        ›  │
│             │   Follow-up two                        ›  │
│             │  ╭─────────────────────────────╮ (↑)      │  glass compose bar
└─────────────┴──╰─────────────────────────────╯──────────┘
```

- **Sidebar "Ideas"**: four starter questions (topic in small secondary text,
  question in body text, emoji icon). The dice button refreshes them. Picking
  one fills the question box and shows the selection; it does not send.
  History will live here later.
- **Detail**: an inline title "Curio" and a subtitle that appears
  only when useful ("Thinking…", "Offline mode", "Not set up yet").
- **Toolbar buttons**: Read aloud (speaker ↔ stop) and Settings (gear),
  separated into two glass buttons.
- **Answer**: the asked question as the heading in the accent colour, the
  answer in a large body size, then "Keep exploring" as a grouped list of
  follow-ups with chevrons. Content is limited to a readable width and
  centred.
- **Compose bar**: a glass text field (1–5 lines) and a round send button
  (↑, prominent glass) that becomes Stop while answering. Return sends. The
  box clears on send; the question becomes the answer's heading.
- **Empty state**: the app icon once, "A little curiosity. A whole world to
  explore.", and a hint.
- **Narrow screens**: one column that opens on the answer; Ideas is one step
  back.
- **Settings**: a sheet with Tutor (menu), Appearance, About, and
  "Advanced (for grown-ups)".

## Tokens

Reconciled with the 2026-09 redesign
([design/redesign-2026-09/curio-redesign-handoff.md](design/redesign-2026-09/curio-redesign-handoff.md));
the redesign wins where they conflict. It applies to the iOS app on both
iPhone and iPad. "Was" records the replaced value.

| Token | Light (design) | Dark (derived, to review) | Was (earlier design) |
| --- | --- | --- | --- |
| Ground (page background) | `#FFF9F0` | `#16142A` | system background |
| Surface (cards, chips, buttons) | `#FFFFFF` | `#221F3A` | `.background.secondary`; controls on glass |
| Border | `#EDE6DA`, 1.5 px | `#38345A` | no borders ("hierarchy from type, not outlines") |
| Ink | `#211E3B` | `#F3F0FF` | `.primary` |
| Muted / labels | `#5B5775` / `#6B6785` | `#BDB8D6` / `#A9A4C4` | `.secondary` |
| Placeholder, disabled icon | `#7A7690` | `#8E89A8` | system |
| Accent as text/icons (brand, Space) | `#4F46C9` | `#B8B0FF` | `#4E45B6` (dark `#C1B2FF`) |
| Accent as fill under white text | `#4F46C9` | `#5E55D8` | same as accent |
| Accent tint / trail connector | `#E6E1FF` / `#CFC8FF` | `#2B2650` / `#4A4480` | accent at 9 % opacity |
| Weather | fill `#DCEBFB`, fg `#1D5FA8` | fill `#1B2B42`, fg `#8CC0F5` | — (emoji only) |
| Animals | fill `#DBF3E3`, fg `#1F7A45` | fill `#173426`, fg `#7FD6A0` | — |
| Space | fill `#E6E1FF`, fg `#4F46C9` | fill `#2B2650`, fg `#B8B0FF` | — |
| Sound | fill `#FFE3D6`, fg `#B8452E` | fill `#3E2219`, fg `#F5A38C` | — |
| Earth *(derived)* | fill `#F1E7D6`, fg `#7A5424` | fill `#33291B`, fg `#E0B98A` | — |
| Electricity *(derived)* | fill `#D9F2F1`, fg `#116B69` | fill `#163332`, fg `#7AD6D2` | — |
| Forces & motion *(derived)* | fill `#FCE1EC`, fg `#A3305F` | fill `#3B1D2B`, fg `#F29BC0` | — |
| Light *(derived)* | fill `#FFF0C7`, fg `#855A00` | fill `#3A3016`, fg `#F2C766` | — |
| Matter *(derived)* | fill `#EEE2F7`, fg `#77389F` | fill `#2F2140`, fg `#D3A6F0` | — |
| Plants *(derived)* | fill `#E6F2D2`, fg `#4A6E12` | fill `#25321A`, fg `#B5D986` | — |
| Success check | `#1F7A45` | `#7FD6A0` | — |
| Locked stamp outline | `#D6CFC2`, 2 px dashed | `#4A4666` | — |
| Heart (credit line) | `#E0554A` | `#F07A70` | ❤️ emoji |
| Display type | Fredoka 500/600/700 | same | San Francisco |
| Body type | Nunito 600/700/800 | same | San Francisco |
| Answer text | 17/26, Nunito 600 | same | `.title3`, line spacing 6 |
| Radius | cards 20, illustration 18, chips 14, bars/pills 24–26 | same | 16 everywhere |
| Touch targets | ≥ 44 px; bar controls 48 | same | system |
| Icons | 2 px stroke, round caps (Lucide-style); no emoji in chrome. iOS uses the closest SF Symbols | same | SF Symbols and emoji |
| Readable width (iPad) | 680 pt | same | unchanged, kept |
| Bottom bar width (iPad) | 720 pt max | same | unchanged, kept |

Implemented in `ios/Curio/CurioTheme.swift`. Fredoka and Nunito (SIL Open Font
License) are bundled in `ios/Curio/Fonts/`. The derived colours keep each
category's hue; check them on the device before treating them as final.

Principles superseded by the redesign: "controls on glass" (controls are now
solid white with a border), "no borders or small spaced capitals" (section
labels are 11–12 px uppercase), "platform colours so Dark Mode works" (fixed
warm palette), and "Answered in N seconds" (dropped as an engineering metric).

Gaps the redesign left open, filled here: colours for the six other bank
topics and all Dark Mode values (both marked derived above).

## Web notes (for the later rollout)

- Sidebar and detail: CSS grid (`280px 1fr`), collapsing to one column with an
  Ideas button below about 700px.
- Glass: a translucent background with `backdrop-filter: blur(...)
  saturate(...)`, a subtle highlight border, and a solid fallback when
  `prefers-reduced-transparency: reduce` or `prefers-contrast: more`.
- Toolbar and compose bar are `position: sticky`; the answer scrolls beneath.
- Keep the current accessibility behaviour: labels, focus rings, `Enter`
  sends, `Shift+Enter` adds a line, and the live status region.
- Do not change the API: the design uses the existing `question`, `answer`,
  and `followUps` fields.
