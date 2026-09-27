# Design

The shared design for Curio. The iPad/iOS app implements it first
(`ios/Curio/ContentView.swift`), following Apple's Human Interface
Guidelines for Liquid Glass (iOS/iPadOS 26 and later). The web page now
uses the same curiosity column in plain TypeScript ([FRONTEND.md](FRONTEND.md)).

> **Tokens** (below) are the single source of truth for phone, iPad and web,
> light and dark. Screen layouts follow the 2026-09 redesign
> ([handoff](design/redesign-2026-09/curio-redesign-handoff.md), dated review
> record); the curiosity-column, principles, layout and web-notes sections
> are the earlier design, superseded where they conflict.

## Screens (2026-09 redesign, implemented)

Layouts of record: `docs/design/redesign-2026-09/*.dc.html`. Feature
decisions (final, 2026-09-26/27): a trail is **5 steps**; each finished
trail earns **one stamp** (no limit; the counter is a total, the row shows
the latest four and a dashed "next"); Sparks are **shuffle-only**; **Show a
grown-up** shares the recap picture plus the trail's questions as text;
stamps and finished trails are kept **on the device only**.

- **Home**: brand and Settings; greeting by first name ("today"/"tonight");
  resume card while a trail is unfinished; Sparks 2×2 with Shuffle; credit.
- **Trail**: Back · topic · "Trail · Step N" · Settings; numbered rail of
  earlier steps; current question, illustration, answer; Dive deeper (two
  on phones). The fifth answer shows Finish instead of the question box.
- **Trail complete**: stamp, "Trail complete!", recap, stamps, Start a new
  spark, Show a grown-up.
- **Responsive** (web and iOS): `<700` phone; `700–1100` phone layout with
  32 px gutters; `≥1100` two columns — Home: 380 px column (greeting, resume
  card with a white Keep going button, "Trails you finished") beside Sparks,
  bar under Sparks; Trail: 340 px side rail (All sparks, identity, every step
  with dashed upcoming steps and the stamp, "So far you know") beside the
  step (heading 34/40, illustration 360×260 beside the answer 20/32, three
  Dive deeper chips). `≥1400` (web): 232 px nav, 300 px rail, step centred
  at 760 px with a 760×280 illustration above the answer.
- Sparks: 2×2 (four) on phones, 3×2 (six, `/api/suggestions?count=6`) at
  ≥1100 px. Deviations: the stamps pill is a count, not a link; the web nav shows Home and My trails only (Stamps and Grown-ups need
  screens); no Complete layout was designed for wide screens, so it stays one
  centred column.
- From the tutor (optional reply fields, 2026-09-27): the step label
  ("Step 3 · The nucleus"), the trail name in headers and stamps ("Comets"),
  and one fact per answer for the recap and "So far you know". When a field
  is missing, the step's question, the spark topic, or the answer's first
  sentence stands in.
- Up to **three unfinished trails** are kept on the device for 7 days: the
  newest as the "Continue your trail" card, earlier ones as small rows under
  it (topic icon, question, "Step N of 5"). Starting a trail sets the current
  one aside; a fourth drops the oldest; finished trails are not kept. There
  is no Undo banner (starting a trail no longer loses one).
- The stamps count pill shows on every layout (phone, iPad, web).
- iOS navigation: Home is the root and Trail / Trail complete are pushed,
  so the system edge swipe goes back to Home.
- Microphone: iOS only, on-device recognition, fills the box (never sends by
  itself). Hidden on the web, where browser speech services may send audio
  to third parties.
- Still a placeholder: the category illustration (not a picture per step).
- **Stamps screen**: 12 kinds (11 topics + Curious Mind, sparkles icon),
  earned with a count or dashed "Not yet", then the latest ten with dates;
  opened from the stamps pill (and the web nav).
- **Delight** (2026-09-27): the new stamp lands with a spring and a pixel
  burst (shader scene 3) on Trail complete, plus a success haptic on iOS;
  up to half the sparks come from topics not yet collected, with a "New
  stamp!" badge once the child has a stamp; while answering, a 3×3 pixel
  "thinking" grid and a "Did you know?" fact every 6 s
  (`backend/data/did-you-know.json`); a one-time welcome (name, sparks /
  trails / stamps, "Let's explore!"), skipped by existing users. All honour
  Reduce Motion.
- **Pixel field** (2026-09-27, after omarchy.org's pixel hero): a band over
  the bottom half of Home and Trail, fixed behind the content (cards cover
  it where they overlap), shows a science scene in 8 pt square pixels,
  densest at the bottom and fading upward, centred in the band above the
  question bar. Home: stars and a comet on phones, the solar system from
  700 px (an atom overlapped the cards). Trail: stars on phones, an atom at
  tablet widths, the solar system on wide web. Earlier wording: a starfield with a comet
  on phones, an atom on tablets, the solar system on wide web (≥1400 px).
  Planets/electrons use topic inks; the field levels are tokens. Trail runs
  it at 45 % opacity; Trail complete has none. Hover glows, a tap ripples.
  Performance rules: drawn by the GPU off the main thread (web: WebGL in a
  worker on an OffscreenCanvas; iOS: a Metal colorEffect), ≤30 fps, paused
  when hidden, a still frame with Reduce Motion.

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

This table is the single source of truth for Curio's design tokens on every
platform. The dated review record is
[design/redesign-2026-09/curio-redesign-handoff.md](design/redesign-2026-09/curio-redesign-handoff.md);
where this table and the handoff disagree, change this table deliberately
and note why. Values without a mark come from the handoff; ᵃ are read from
its iPad/web artboards (dark derived); ᵈ are derived here.

- **Web**: CSS custom properties at the top of `public/styles.css`. Light on
  `:root`; dark under `:root[data-theme="dark"]` and under
  `prefers-color-scheme: dark` when no theme is set. `theme.ts` sets
  `data-theme` from the Light/Dark/System choice before the first paint.
- **iOS**: colour sets with Any/Dark appearances in
  `ios/Curio/Assets.xcassets/Colors/`, read through `Curio.*` in
  `CurioTheme.swift`. The app's Light/Dark/System setting overrides the
  window style, so the sets follow it. `Accent.colorset` (the app tint for
  system controls) matches `accent-text`.
- Do not write literal colours in screens; add a token here first.

### Colour

| Token (CSS `--name` · iOS colour set) | Light | Dark | Use |
| --- | --- | --- | --- |
| `ground` · `Ground` | `#FFF9F0` | `#17152A` | Page background |
| `surface` · `Surface` | `#FFFFFF` | `#221F3A` | Cards, inputs, pills, round buttons |
| `border` · `Border` | `#EDE6DA` | `#332F52` | 1.5 px outlines; disabled Send fill |
| `ink` · `Ink` | `#211E3B` | `#F3F0FF` | Body text |
| `muted` · `Muted` | `#5B5775` | `#A9A4C6` | Secondary text, earlier-step rows |
| `label` · `Label` | `#6B6785` | `#8E89AE` | Captions, section labels, credit line |
| `placeholder` · `Placeholder` | `#7A7690` | `#8E89AE` | Input placeholder; disabled Send icon |
| `accent-fill` · `AccentFill` | `#4F46C9` | `#6A61E8` | Buttons, resume card, current-step disc (never `#4F46C9` on dark) |
| `on-accent` · `OnAccent` | `#FFFFFF` | `#FFFFFF` | Text and icons on accent fill |
| `accent-text` · `AccentText` | `#4F46C9` | `#A9A2FF` | Links, chips, icons on ground/surface; focus ring; iOS app tint |
| `accent-heading` · `AccentHeading` | `#4F46C9` | `#B1AAFF` | Current question heading |
| `accent-tint` · `AccentTint` | `#E6E1FF` | `#2A2652` | Earlier-step discs, active nav item, Space fill |
| `connector` · `Connector` | `#CFC8FF` | `#3E3870` | Trail rail between done steps |
| `upcoming-connector` · `UpcomingConnector` ᵃ | `#E4DFD3` | `#332F52` | Rail toward upcoming steps (iPad/web) |
| `upcoming` · `Upcoming` ᵃ | `#9A95B5` | `#8E89AE` | Upcoming-step text (iPad/web) |
| `locked` · `Locked` | `#D6CFC2` | `#3E3870` | Dashed outlines: locked stamp, upcoming disc |
| `success` · `Success` | `#1F7A45` | `#6FCF97` | Recap check marks |
| `heart` · `Heart` | `#E0554A` | `#FF7A6E` | Credit-line heart |
| `icon-disc` · `IconDisc` | `#FFFFFF` | `#17152A` | Behind category icons (dark: a ground cut-out) |
| `sun` · `Sun` | `#FFCF6E` | `#FFCF6E` | The Sun in illustrations |
| `sparkle` · `Sparkle` | `#FFFFFF` | `#F3F0FF` | Stars and dust in illustrations |
| `danger` · `Danger` ᵈ | `#B3261E` | `#FF9A93` | Error text |
| `danger-tint` · `DangerTint` ᵈ | `#FDECEA` | `#3A1F24` | Error background |
| `scrim` (CSS only) | ink at 40 % | black at 55 % | Behind dialogs |
| `halo-opacity` (CSS; iOS in code) | 0.5 | 0.12 | Glow behind the illustration disc |
| `field-dim` · `FieldDim` | `#EFE8F3` | `#221F3B` | Pixel field, faintest level |
| `field-mid` · `FieldMid` | `#E2D9F6` | `#2D2952` | Pixel field |
| `field-lit` · `FieldLit` | `#C3B8F4` | `#474093` | Pixel field, orbits and comet tail |
| `field-crest` · `FieldCrest` | `#8F85EA` | `#8A82F5` | Pixel field, brightest (comet head, hover) |

### Categories

Spark cards, stamps, and illustration fills. The bank's ten topics plus the
handoff's Body (not yet in the bank).

| Topic | CSS `--{key}-fill` / `-ink` · iOS `{Name}Fill` / `{Name}Ink` | Light fill / ink | Dark fill / ink | Icon |
| --- | --- | --- | --- | --- |
| Weather | `weather` · `Weather` | `#DCEBFB` / `#1D5FA8` | `#1C2E48` / `#8FC3FF` | cloud-sun |
| Animals | `animals` · `Animals` | `#DBF3E3` / `#1F7A45` | `#1B3326` / `#7ED9A1` | fish |
| Space | `space` · `Space` | `#E6E1FF` / `#4F46C9` | `#2A2652` / `#B1AAFF` | comet (iOS `moon.stars`) |
| Sound | `sound` · `Sound` | `#FFE3D6` / `#B8452E` | `#3D2420` / `#FFA48D` | music note |
| Light | `light` · `Light` | `#FCEBC4` / `#8A5A00` | `#3A2E12` / `#FFD37A` | light bulb |
| Body | `body` · `Body` | `#FADCE8` / `#A8336B` | `#3B1F2D` / `#FF9CC4` | heart |
| Earth ᵈ | `earth` · `Earth` | `#F1E7D6` / `#7A5424` | `#33291B` / `#E0B98A` | mountain |
| Electricity ᵈ | `electricity` · `Electricity` | `#D9F2F1` / `#116B69` | `#163332` / `#7AD6D2` | bolt |
| Forces & motion ᵈ | `forces` · `Forces` | `#E3E8EF` / `#3E5A7A` | `#1F2733` / `#A9C1DD` | move arrows |
| Matter ᵈ | `matter` · `Matter` | `#EEE2F7` / `#77389F` | `#2F2140` / `#D3A6F0` | atom |
| Plants ᵈ | `plants` · `Plants` | `#E6F2D2` / `#4A6E12` | `#25321A` / `#B5D986` | leaf |

### Type, shape, spacing

| Token | Value |
| --- | --- |
| Display type | Fredoka 500/600/700 (`--font-display`) |
| Body type | Nunito 600/700/800 (`--font-body`); default weight 600 |
| Fonts | Self-hosted, SIL Open Font License: `public/fonts/` (woff2, latin + latin-ext) and `ios/Curio/Fonts/` (variable TTF) |
| Answer text | 17/26 phone, 20/32 iPad and web; weight 600 |
| Radius | cards 20, illustration 18, chips 14, bars and pills 24–26 |
| Border | 1.5 px `border` |
| Elevation | none: no shadows in either mode, only border + surface |
| Touch targets | ≥ 44 px; bar controls 48 (phone) / 52 (iPad, web) |
| Icons | 2 px stroke, round caps (Lucide-style); no emoji in chrome. iOS uses the closest SF Symbols |
| Breakpoints | `<700` phone · `700–1100` phone layout, wider gutters · `≥1100` two columns · `≥1400` three columns with nav |

### Known contrast gaps (kept as designed)

WCAG AA asks 4.5:1 for small text. On light: Sound ink on its fill 4.38:1,
placeholder on surface 4.36:1, upcoming-step text on surface 2.86:1. Every
other pair above passes (white on dark accent fill: 4.68:1).

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
