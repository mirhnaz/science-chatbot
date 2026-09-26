# Design

The shared design for Science Chatbot. The iPad/iOS app implements it first
(`ios/ScienceChatbot/ContentView.swift`), following Apple's Human Interface
Guidelines for Liquid Glass (iOS/iPadOS 26 and later). The web app will adopt
the same structure later; the web notes below say how. Until then, the web keeps
its current two-panel layout ([FRONTEND.md](FRONTEND.md)).

## The curiosity column (current iPad build)

[design/curiosity-column.png](design/curiosity-column.png) (source:
[design/curiosity-column.html](design/curiosity-column.html)) replaces the
Ideas sidebar with one column where every "what next?" choice sits near the
question box. Built in `ios/ScienceChatbot/ContentView.swift`:

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
- **One accent.** A Nord frost blue is the only accent; backgrounds, surfaces,
  and text come from the Nord palette in light and dark (see Colours).
- **For 10–13 year olds.** No technical wording on the main screen (engine
  names, timings). Large, readable answer text.

## Layout

```text
┌─────────────┬───────────────────────────────────────────┐
│ Ideas   🎲  │          Science Chatbot        🔊   ⚙︎   │  glass toolbar
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
- **Detail**: an inline title "Science Chatbot" and a subtitle that appears
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

## Colours: Nord

Both apps use the [Nord](https://www.nordtheme.com/) palette. iOS colour sets
live in `ios/ScienceChatbot/Assets.xcassets`; the web should use the same hex
values as CSS custom properties. All text pairs meet WCAG AA (4.5:1).

| Role | Light | Dark | Contrast |
| --- | --- | --- | --- |
| Background | nord6 `#ECEFF4` | nord0 `#2E3440` | — |
| Surface (cards, rows) | nord5 `#E5E9F0` | nord1 `#3B4252` | — |
| Text (Ink) | nord0 `#2E3440` | nord6 `#ECEFF4` | 10.8 / 10.8 |
| Accent | nord10 deepened `#476791` | nord8 `#88C0D0` | 5.0 / 6.2 |
| Text on accent | nord6 `#ECEFF4` | nord0 `#2E3440` | 5.0 / 6.2 |
| Error | nord11 deepened `#9E434B` | nord11 lightened `#E3959C` | 5.4 / 5.4 |

Official nord10 (`#5E81AC`) is only 3.5:1 on nord6, too low for the
question headings and Dive deeper rows children read, so the light accent is
a deeper shade of it. Secondary text is the Ink colour at reduced opacity.

## Tokens

| Token | iOS | Web equivalent |
| --- | --- | --- |
| Accent | `Accent` colour set (Nord, see Colours) | CSS `--accent` |
| Text / secondary text | `.primary` / `.secondary` | `CanvasText` / muted token per theme |
| Grouped rows | `.background.secondary`, radius 16 | card background token, radius 16px |
| Readable width | 680 pt | `max-width: 680px` |
| Compose bar width | 720 pt max | `max-width: 720px` |
| Answer text | `.title3`, line spacing 6 | ~20px, line-height ~1.55 |
| Font | San Francisco (system) | `system-ui, -apple-system, sans-serif` |

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
