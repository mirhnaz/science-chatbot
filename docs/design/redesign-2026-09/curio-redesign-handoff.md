# Curio — redesign handoff (2026-09-26)

Source: design review of Home and Trail screens (iOS build, 26 Sep 2026). Redesign published as a Claude Design canvas with three artboards: `Main.dc.html` (Home), `Trail.dc.html` (Trail step), `Complete.dc.html` (Trail complete). Each is self-contained HTML; the markup inside `<x-dc>` is the layout of record. Ignore the `<script src="./support.js">` line and the `data-dc-script` block — they are the design tool's runtime. `{{accent}}` resolves to `#4F46C9`.

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

## Open decisions
- Sparks rotation: daily fixed set vs shuffle-only. Daily set gives a return trigger.
- Parent digest: weekly "what {name} learned" surfaced from the resume card or Settings.
- Trail length: fixed (e.g. 5) vs open-ended. Progress dots assume a known length.
- Stamp count and categories: 12 is a placeholder.
