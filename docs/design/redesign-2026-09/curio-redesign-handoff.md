# Curio — redesign handoff (2026-09-26)

Source: design review of Home and Trail screens (iOS build, 26 Sep 2026). Redesign published as a Claude Design canvas with eight artboards:

| File | Screen | Size | Theme |
|---|---|---|---|
| `Main.dc.html` | Home | 390×844 | light |
| `Trail.dc.html` | Trail step 3 | 390×844 | light |
| `Complete.dc.html` | Trail complete | 390×844 | light |
| `MainDark.dc.html` | Home | 390×844 | dark |
| `TrailDark.dc.html` | Trail step 3 | 390×844 | dark |
| `TabletHome.dc.html` | Home | 1180×820 | light |
| `TabletTrail.dc.html` | Trail step 3 | 1180×820 | light |
| `WebTrail.dc.html` | Trail step 3 | 1440×900 | light |

Each is self-contained HTML; the markup inside `<x-dc>` is the layout of record. Ignore the `<script src="./support.js">` line and the `data-dc-script` block — they are the design tool's runtime. `{{accent}}` resolves to `#4F46C9` on light boards and `#6A61E8` on dark boards.

## Critique of current build

### Home
1. Hero (icon + two-line tagline) consumes ~40% of viewport; sparks fall below the fold on smaller phones. Tagline is adult marketing voice.
2. Visual register mismatch: saturated playful icon over grayscale iOS-default rows. Reads like Settings.
3. Four identical gray cards, each a full sentence. Not scannable for pre-readers; flat for 10–13s. Category emoji is tiny gray metadata.
4. `New sparks` (core engagement loop) styled as tertiary pill below the list.
5. No memory / resume state. Returning user sees the same page.
6. Text input is the lowest-probability entry point for this age. No mic. Send arrow renders as heavy disabled gray disc.

### Trail
1. Rendering bug: `New spark` label overlaps Dive-deeper card text. Root cause: three stacked bottom regions (Dive deeper, New-spark carousel, input).
2. Trail metaphor not visualised; collapsed prior steps read as a chat log.
3. `Answered in 1.3 seconds` is an engineering metric; meaningless to the user.
4. No visuals on inherently visual topics.
5. No end state, no completion, no collection.
6. `Ask your own` and the text input are redundant.

## Design decisions

### Home (`Main.dc.html`)
- Remove hero and tagline. Single H1, kid-addressed, personalised with first name: "What are you curious about today, {name}?"
- **Resume card** (top, accent fill): label CONTINUE YOUR TRAIL, trail question, 5 progress dots (filled = completed), "Step N · {short label}", "Keep going" → opens trail at current step. Show only when an unfinished trail exists; otherwise sparks move up.
- **Sparks**: 2×2 grid, 148px cards, radius 20, category tint fill, 40px white icon disc top-left, category label 11px/800 uppercase in category colour, question 15px/700. Whole card is the tap target.
- **Shuffle** button in the Sparks header row (right), replaces bottom `New sparks` pill.
- Bottom bar: mic (48) · input (48, radius 24) · send (48, accent). Send is accent-filled only when input has text; otherwise `#EDE6DA` fill, `#7A7690` icon.
- Credit line retained, 12px, `#6B6785`, above the bar. Move to Settings › About if space is tight on SE-class devices.

### Trail (`Trail.dc.html`)
- Header: back (44) · centre stack "Trail name" 17px Fredoka + "TRAIL · STEP N" 12px uppercase · settings (44). Drop the timing metric.
- **Step rail**: prior steps as 40px rows — 26px numbered disc (tint `#E6E1FF`, text accent) + one-line truncated question + chevron-down; 2px connector `#CFC8FF` between rows. Current step: filled accent disc, question as H1 24/29 Fredoka in accent.
- **Illustration slot**: 124px, radius 18, tint fill, one flat SVG per step with ≤2 labels. Generate per-topic or fall back to category illustration.
- Answer: 17/26, weight 600, ink `#211E3B`. Target ≤6 lines on 390px.
- **Dive deeper**: label 15px Fredoka muted, then 2 full-width chips (min 48px, white, 1.5px border, accent text, chevron). Directly under the answer. Remove `Ask your own` and the New-spark carousel from this screen.
- Bottom bar identical to Home; placeholder "Ask more about {topic}…".
- Speaker (read-aloud) button 44px, right of the question.

### Trail complete (`Complete.dc.html`) — new screen
- Trigger: user finishes a trail (define: N steps reached or no further dive-deeper offered).
- 156px stamp disc (tint fill, 5px accent ring, category icon). H1 "Trail complete!" 30px. One-line sub.
- **Recap card**: 3 bullet facts from the trail (green check icons). Generate from step answers.
- **Stamps row**: earned stamps as 56px tinted discs; locked as dashed `#D6CFC2` outlines. Counter "3 of 12".
- Actions: primary "Start a new spark" (52px, accent) → Home; secondary "Show a grown-up" (share sheet: recap card as image).

## Tokens

| Token | Value |
|---|---|
| Ground | `#FFF9F0` |
| Surface | `#FFFFFF` |
| Border | `#EDE6DA` (1.5px) |
| Ink | `#211E3B` |
| Muted | `#5B5775` / labels `#6B6785` |
| Accent (Space / brand) | `#4F46C9` |
| Weather | fill `#DCEBFB`, fg `#1D5FA8` |
| Animals | fill `#DBF3E3`, fg `#1F7A45` |
| Space | fill `#E6E1FF`, fg `#4F46C9` |
| Sound | fill `#FFE3D6`, fg `#B8452E` |
| Display type | Fredoka 500/600/700 |
| Body type | Nunito 600/700/800 |
| Radius | cards 20, chips 14, pills/bars 24–26 |
| Touch targets | ≥44px |

Icons: stroke SVG, 2px, round caps (Lucide-style). No emoji in UI chrome.

## Dark mode tokens

Not pure black: kids' app, warm-indigo dark keeps the brand. All pairs below pass WCAG AA (≥4.5:1 body, ≥3:1 large/UI).

| Token | Light | Dark |
|---|---|---|
| Ground | `#FFF9F0` | `#17152A` |
| Surface (cards, inputs, pills) | `#FFFFFF` | `#221F3A` |
| Border | `#EDE6DA` | `#332F52` |
| Ink | `#211E3B` | `#F3F0FF` |
| Muted text | `#5B5775` | `#A9A4C6` |
| Label / caption | `#6B6785` | `#8E89AE` |
| Accent fill (buttons, resume card, current-step disc) | `#4F46C9` | `#6A61E8` (white text on it: 5.0:1) |
| Accent text/icon on ground | `#4F46C9` | `#A9A2FF` |
| Accent H1 (current question) | `#4F46C9` | `#B1AAFF` |
| Rail connector | `#CFC8FF` | `#3E3870` |
| Locked / dashed | `#D6CFC2` | `#3E3870` |
| Success check | `#1F7A45` | `#6FCF97` |
| Heart (credit line) | `#E0554A` | `#FF7A6E` |
| Weather | fill `#DCEBFB` fg `#1D5FA8` | fill `#1C2E48` fg `#8FC3FF` |
| Animals | fill `#DBF3E3` fg `#1F7A45` | fill `#1B3326` fg `#7ED9A1` |
| Space | fill `#E6E1FF` fg `#4F46C9` | fill `#2A2652` fg `#B1AAFF` |
| Sound | fill `#FFE3D6` fg `#B8452E` | fill `#3D2420` fg `#FFA48D` |
| Light (new) | fill `#FCEBC4` fg `#8A5A00` | fill `#3A2E12` fg `#FFD37A` |
| Body (new) | fill `#FADCE8` fg `#A8336B` | fill `#3B1F2D` fg `#FF9CC4` |

Rules:
- Icon discs inside spark cards: light uses `#FFFFFF`; dark uses Ground `#17152A` (not Surface) so the disc reads as a cut-out.
- Illustration slot: tints drop to the dark category fill; star/dust marks use Ink at reduced opacity; the Sun stays `#FFCF6E` in both.
- Accent fill on dark is deliberately lighter than light-mode accent. Do not reuse `#4F46C9` as a fill on dark — 3.4:1 against white text.
- Shadows: none in either mode. Elevation is border + surface only.
- iOS: map to semantic colours via asset catalog (`Any / Dark` appearance); web: `prefers-color-scheme` + `data-theme` override; the kid should be able to pick in Settings regardless of system.

## iPad (landscape 1180×820) and Web (1440×900)

Breakpoints: `<700` phone · `700–1100` iPad portrait (phone layout, wider gutters, 3-col sparks) · `≥1100` two-column · `≥1400` web three-column with persistent nav.

### iPad Home (`TabletHome.dc.html`)
- 40px gutters, two columns: left 380px fixed, right fluid, 32px gap.
- Left: H1 34/40 · resume card (with a white "Keep going" button inside, 46px) · "Trails you finished" list card.
- Right: Sparks header + Shuffle · 3×2 grid, cards 186px tall, 48px icon disc, question 17/22 · input bar 52px pinned bottom.
- Six sparks on tablet (two new categories, Light and Body). Header adds a `3 stamps` pill linking to the stamps screen.

### iPad Trail (`TabletTrail.dc.html`)
- Left rail 340px, white surface, right border. Contents: back link ("All sparks") · trail identity (48px disc, name, "SPACE TRAIL · 3 OF 5") · full step list: completed (tint disc), current (highlighted row, accent disc), upcoming (dashed discs, "Next step", "Comet stamp") · "So far you know" recap card pinned bottom.
- Main: H1 34/40 in accent + speaker · illustration 360×260 beside answer 20/32 · Dive deeper 3-across, 64px chips · input bar 52px.
- Trail length becomes visible here (dashed future steps) — this is where the "fixed vs open-ended" open decision bites.

### Web Trail (`WebTrail.dc.html`)
- Three columns: nav 232px (white) · rail 300px · main fluid with 760px max content width, centred.
- Nav: Curio mark, Home / My trails / Stamps / Grown-ups, active item tinted `#E6E1FF`, profile chip bottom. "Grown-ups" is the parent digest entry point (open decision from v1).
- Rail identical to iPad rail. Main identical to iPad main with wider illustration (760×280) and answer below it rather than beside.
- Web has no bottom safe-area; input bar sits 28px from the bottom edge.

### Shared responsive rules
- Illustration: `aspect-ratio` 350:124 phone, 360:260 tablet side-by-side, 760:280 web full-width. Serve the same SVG with `preserveAspectRatio="xMidYMid slice"`, or author three crops.
- Rail steps collapse to the phone's stacked rows below 1100px.
- Touch targets stay ≥44px at all sizes; pointer devices get `:hover` on cards (surface lift via border colour → accent, no shadow).

## Open decisions
- Sparks rotation: daily fixed set vs shuffle-only. Daily set gives a return trigger.
- Parent digest: weekly "what {name} learned" surfaced from the resume card or Settings.
- Trail length: fixed (e.g. 5) vs open-ended. Progress dots assume a known length.
- Stamp count and categories: 12 is a placeholder.
