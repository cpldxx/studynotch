# StudyNotch design system

The app (the Mac notch) and the website follow the same rules. Read this before making or changing a screen.

## Overview

StudyNotch is a tool that sits next to a student reading a textbook, so its visual language comes from the desk: white paper, blue-black pen ink and a highlighter. The product also works like a highlighter: mark a sentence you don’t get, and an explanation comes.

- The app is white and grey on black (the user's call, 2026-11-19). White marks "press this now", "the text you picked" and "how much you’ve done" (the progress ring, today’s bar, the running course’s dot). The mascot is black with white eyes.
- One spoonful of colour: a faint light rising behind a card, the question window and the mascot, in the state's colour (Glow, below). It is only ever a soft gradient, never a fill, a dot, a border or text. Nothing else in the app has colour.
- Highlighter yellow belongs to the website (its buttons, headline marks and the demo textbook's picked sentence), not to the app.
- The notch island is always pure black, so it reads as one piece with the hardware notch. Only the cards inside the island are a little lighter, #141518.
- The screen never covers the book you’re reading. Point at it and it peeks out; it opens only when clicked; let go and it backs away by itself after 15 seconds.
- The island’s structure and motion follow Coucou (MIT). The mascot, colours, words and sounds are ours.
- The mascot, Squat, is a small round body of glossy black drawn in 3D by code, with two white painted eyes that follow the pointer. On the first screen it sits on top of the Mac screen and jumps into the island when it opens. This is the one thing on the page that stands out.

## Colors

### Brand & Accent

| Name | Value | Used for |
|---|---|---|
| Highlighter | `#FFE94A` | Website only: the most important button, headline marks, the picked sentence on the demo page, the current step’s number in the tour. Not used in the app |
| Pen Blue | `#1F4FD8` | Web links and focus rings |

### Surface

| Name | Value | Used for |
|---|---|---|
| Paper | `#FFFFFF` | Web background |
| Desk | `#EDF0F3` | Bands that divide web sections, the desk in the demo screen |
| Island | `#000000` | The notch island (app, web demo) |
| Island Fill | White 12% (8% for buttons inside cards) | Button backgrounds inside the island |
| Card | `#141518`, border white 3.5% | Cards in the open island. Always plain: no coloured wash |
| Pill | `#0E0F11` | Course pill background |
| Tab On | `#1D1F23` | Selected tab background |

### Text

| Name | Value | Used for |
|---|---|---|
| Ink | `#14233B` | Web body and headings (blue-black ink) |
| Graphite | `#566173` | Secondary web text (pencil) |
| Island Text | `#F5F6F8` | Island body text |
| Island Muted | `#8E939C` | Secondary island text, idle icons |
| Island Faint | `#6B7079` | The faintest text, like the weekdays under the record bars |

### Glow (app states)

The app's one spoonful of colour. Each state colours only a faint light: the wash rising from the bottom of a card (and of the question window), and the soft light behind the mascot. Never a fill, a dot, a border or text. A state is never shown by colour alone either: the mascot's eyes change shape and the words change too.

| State | Glow | Mascot's eyes |
|---|---|---|
| Focus | `#7CE38B` at 32% | Half closed |
| Drift | `#FFB25E` at 40% | Wide, looking away |
| Writing an answer | `#C9A6FF` at 22% (question window) | Looking up and to the right |
| Break | White at 10% | Asleep |
| Session done | `#7CE38B` at 40% | Smiling |

Courses have no colours. They are told apart by their names.

## Typography

### Font Family

- Web headings: **Hahmlet** (700). A serif like a textbook’s body type, so it feels like a book.
- Web body: **IBM Plex Sans KR** (400, 500, 600).
- The mascot’s voice: **Gaegu** (700). Only in the web mascot’s speech bubble, where it should look like a note written in pencil. Nowhere else.
- App: the Mac system font. The app should look like part of the Mac.
- Monospace only for code and commands.

### Hierarchy

| Role | Web | App |
|---|---|---|
| Large heading | Hahmlet 700, clamp(36px, 6vw, 64px), line height 1.15, tracking -0.02em. On the first page, with the screen beside it, clamp(38px, 4.3vw, 58px) | Not used |
| Section heading | Hahmlet 700, clamp(26px, 3.4vw, 38px) | 14pt semibold |
| Body | 17px, line height 1.75, lines at most 38em | 13pt (answers 14pt, line height 1.6) |
| Card title | Not used | 12.5pt semibold |
| Big number (time left, record) | Not used | 21pt semibold, tabular |
| Secondary text | 14.5px Graphite | 11.5pt Island Muted |
| Button | 15px 600 | 11.5pt semibold in cards, 12.5pt in the question window |
| Pill label | Not used | 11pt semibold |
| Mascot bubble | Gaegu 700, 21px (phone 19px), line height 1.25 | System font 11.5pt semibold |

### Principles

- The website and the app are in English (the app since 2026-11-19). Answers come back in the language the question is typed in, so they can be Korean, and the web fonts (Hahmlet, IBM Plex Sans KR) keep their Korean glyphs. Keep English headings short: the first screen’s large heading is at most three lines, other headings one.
- English runs longer than Korean. In the island, a label that doesn’t fit is shortened, not shrunk below the sizes here (a little scaling, at most to 0.8, is allowed for one-line labels). Render every state after changing words.
- No text smaller than 12px on the web or 11pt in the island. The island is dense, like Coucou’s, so it fits beside the notch.
- No eyebrow labels above headings. No all-caps labels.
- Never recolour or italicise a single word in a heading. The highlighter goes across the whole sentence.
- Tabular numbers wherever digits need to line up.

## Layout

### Spacing System

Multiples of 4: 4, 8, 12, 16, 24, 32, 48, 72, 112.
Tight inside a group (8–12), wide between groups (48 or more). More space above a heading than below it.

### Grid & Container

- Web: the first page is at most 1264px wide (the screen picture has to hold the 640pt island), docs 1120px. Side margins 24px (20px on mobile). Left-aligned by default; on one page the header, every section and the footer start on the same left line.
- First screen: words on the left, the Mac screen on the right with the seven steps under it. The Mac screen’s height follows the window between 400 and 548px, so on a laptop the step’s description fits on the same screen.
- Open island: 640pt wide. 8pt at the top plus a 34pt tab strip, then the card area (10pt left and right, 10pt at the bottom). Home, Record and Add have a 322pt left card, a 10pt gap and a right card.
- Text in a card starts 98pt from the left. The space before it is the mascot’s.
- Folded island: the notch’s width plus an 80pt ear on each side. The mascot in the middle of the left ear, time left (or today’s minutes) in the middle of the right ear.

### Whitespace Philosophy

The textbook’s "body plus margin notes" structure: short notes in a narrow column beside the body. Don’t chop content into many cards of the same size.

## Elevation & Depth

- The web uses almost no shadows. Separation comes from the Desk background and 1px rules.
- Only the demo’s Mac screen has a shadow, because it is the one "object" on the page. The web mascot has one shadow, where it touches the ground (none inside the island).
- The island has no shadows and no glows. Things under the pointer brighten a little instead.

## Shapes

| Item | Rounding |
|---|---|
| Island (folded) | Bottom corners 12pt; the top corners are concave ears (10pt) flowing into the screen edge |
| Bar on a screen without a notch | 80×24pt, no taller than the menu bar |
| Island (open) | 640pt wide, bottom corners 22pt, square at the top |
| Card | 20pt |
| Course pill | Full pill, 28pt high |
| Button in a card | Full pill, 26pt high |
| Tab | 30×22pt pill |
| Question window buttons (chips) | Full pill, at least 28pt high |
| Text fields, list rows | 8–10pt |
| Web buttons, tour steps, mood buttons | 10px |
| The web’s Mac screen | 8px black bezel, 24px rounding (phone 6px, 20px). The "stays on your Mac" box uses the same bezel |
| Mood stage | 24px |
| Web figure and table frames | 14px |

## Components

### Buttons

- **Primary**: Highlighter background, black text. One per screen.
- **Secondary**: in the app, Island Fill with white text; on the web, a 1px Ink border.
- A button says exactly what happens when you press it: "I don’t get this", "Back to work", "One more".
- No arrows at the end of button labels.

### Picked text (Quote)

A picked sentence looks highlighted. In the app, Highlighter-coloured text on a Highlighter 16% background; on the web, a Highlighter band behind the text.

### Open island (app)

- **Tab strip**: Home, Record and Add tabs left of the notch. On the right, a session pill (during a session, when not on Home), then sounds, connections and permissions, and close icons.
- **Card**: title row (colour dot + name + secondary text) → big number and the primary button → a row of secondary buttons. One primary button per card.
- **Course pill**: the name only. The picked course is a lighter pill (Tab On) with white text; the others are grey. The course in session shows time left and a Highlighter dot instead of its name.
- **Add tab**: 204pt tall (the other tabs are 160pt), so its list fits; the mascot stays where it is on the other tabs. Left card: title, a name field with one button (Add, or Rename), "Link folder" and "Add PDFs", then one quiet line. Right card: a dashed drop zone that becomes the list of folders and PDFs, each row with a ✕. The new-course page says picked things are "Kept only if you press Add".
- **Countdown line**: bottom centre of an open island the pointer has left. Shrinks from 160pt to 0 over the last 10 seconds.
- **Line under the island**: point at the folded island and a one-line summary appears below it in a black pill. Notices use the same place for 2.5 seconds.

### Question window (app)

Header (mascot + Ask + context + a pill showing which AI answers + close) → picked text → my question as a bubble (right) → answer → buttons → text field. While waiting: three purple dots and a status line with a light sweeping across it. "Send" sits inside the text field’s pill.

### Navigation (web)

One row at the top: name, docs, get started. Doc pages have a table of contents on the left.

### Signature Components

- **Notch island**: the black shape at the top centre of the screen. Springs between three sizes: hidden, peek and open.
- **Highlighter stroke**: drawn behind the text from left to right, the second line after the first (0.9 seconds).
- **Tour**: seven scenes from one study hour. A numbered button switches the Mac screen above to that scene, and its description appears right below. The scenes are a real sequence, so they are numbered.
- **Mascot**: see below.

### Mascot

Squat: a small round body of glossy black, no feet. Its face is two white eyes and nothing else. The eyes are painted on its surface, flat, upright, perfect ovals, and they follow the pointer: they slide toward it and the body turns toward it (up to 0.2 rad), so the eyes travel about 12% of the body's width each way. The two must add up, never cancel. Drawn new for StudyNotch. Squat is a working name. The user chose the round body, the white eyes and the eyes that follow the pointer (2026-11-19).

It is drawn in 3D by code every time, from the same numbers on the web and in the app: a rounded shape described by distances, lit by one studio (a big soft light up and to the left, a cool strip behind on the right). No image files and no outside library: WebGL on the web (`site/assets/squat.js`), Metal in the app (`Sources/StudyNotch/MascotRenderer.swift`). The two shaders are the same program and change together.

Shape and colour:

- Body: black with a clear coat. Most of what you see is the studio reflected in it, plus a cool rim on the far edge so it still reads on the island's black.
- Eyes: always white (Island Text). Ovals 0.075 wide and 0.132 tall (half sizes, in body units; the body is 0.96 wide), 0.34 apart, a little above the middle. Sad and cross eyes are longer, 0.07 × 0.15. The smile is a tall arch, thick in the middle and narrowing to fine points at both ends; asleep is a shallow dip drawn the same way. The user set these sizes by hand.
- Close to Coucou's Mochi and to other notch pets ("eyes on a black shape in the notch, following the cursor"). Keep what is ours: the glossy 3D round body, flat painted eyes, no poke-to-annoy reactions, no wardrobe, and the behaviour of a study companion.

| Expression | When | Eyes | Body |
|---|---|---|---|
| Rest | Outside a session | Ovals, following the pointer | Upright |
| Glad | Pointed at, speaking, the greeting | Smile | Upright |
| Focus | During a session | Half closed, a little down, following the pointer | Settles 3% |
| Thinking | While the question window writes an answer | Looking up and right | Leans back |
| Drift | Drift card, while drifting | Wide | Leans |
| Break | On a break | Asleep | Settles 8% |
| Session done | Summary card | Smile | Stands 4% taller |
| Sad | Not used yet | Lids lower at the outer corners | Settles |
| Cross | Not used yet | Lids lower at the inner corners | Upright |

What it does, on the web and in the app:

- Its oval eyes follow the pointer (up to 1.5 eye-steps sideways), easing over 0.16 seconds; its body turns a little toward it (up to 17°). A smile and sleeping eyes stay put.
- Blinks at random every 2–6 seconds; when the pointer is still, it sometimes glances to one side.
- Changing expression: sizes ease over 0.4 seconds; when the eye shape changes (oval, smile, asleep) it swaps in the middle of a blink.
- It draws frames only while something moves. Off screen, or with "Reduce motion" on, it stays still and changes expression at once.

Where it lives on the web (sizes are heights): the left end of the top bezel of the first screen's Mac (108–136px, phone 104px), the open island's card (54px), the folded island's left ear (20px), the mood stage (190px), next to "Get started" at the end of the page (150px).

What it does on the web:

- Press it and it squashes a little, then hops.
- When the island opens it jumps from the bezel to its place in the island, and climbs back when it folds. Its place on the bezel is right above its place in the island, so the jump is short and never crosses other content.
- It speaks only through one pencil note above the screen. The note says what to press next and appears after the mascot has landed.
- The mascot at the end of the page smiles when the pointer reaches "Get started".

Where it lives in the app (sizes are heights): the middle of the bar on a screen without a notch (18pt), the folded island's left ear (20pt), left of the open card (54pt, at x = 64pt), the connection check card (50pt), the greeting (60pt, centred), the question window header (22pt). Hidden on a notched screen while the island is hidden.

What it does in the app:

- Moves between places on the same spring as the island (0.5 seconds, damping 0.72).
- Press it in the open island and it crouches, hops, and says something short in a paper bubble (2.2 seconds). Point at it and it smiles.

## Do's and Don'ts

### Do

- Use highlighter yellow sparingly.
- On a failure screen, say why and what to do next.
- Show a state with shape and words together.
- Show the real app screens as they are.

### Don't

- Gradient text, glass effects, decorative shadows.
- Grids of identical cards on the web. (The island’s course pill grid is an exception, following Coucou.)
- Eyebrow labels above headings, 01/02/03 numbering (number only a real sequence).
- Boxes with a coloured stripe down one side.
- Testimonials, user counts or logo strips that don’t exist. Facts only.
- A character that resembles Coucou or Mochi.

## Responsive Behavior

### Breakpoints

- 900px and below: margin notes move under the body. The docs’ table of contents moves to the top.
- 1000px and below: the first screen becomes one column: words, Mac screen, seven steps, description.
- 760px and below, and 1001–1240px: the seven step names don’t fit on one row, so only the numbers stay and the step’s name goes in front of its description. Never wrap onto two rows.
- 600px and below: the Mac screen drops to 480px high and the open island shows only the left card. One-card states (drift, session done) grow to 204px so their text isn’t cut.
- 560px and below: the demo screen shrinks to the screen width, and of the two "Get started" buttons only the first screen’s stays.

### Touch Targets

At least 44px high on the web. App chips at least 28pt high, at least 6pt apart.

## Motion

- Web: when the page opens, the highlighter stroke is drawn and the mascot lands on top of the screen. After that, only reactions to what the user does move. The one exception is the mascot’s breathing and blinking.
  - When the mascot moves: a spring (stiffness 120, damping 16) with a small 0.46-second arc on top, and a 0.28-second squash on landing.
  - When pressed: a 0.1-second squash, a 0.62-second hop and one spin (spring 110/13). Pressing quickly many times never stacks more than one spin.
  - Buttons scale to 0.97 when pressed (0.12 seconds). Hover changes only on devices with a mouse.
  - Content inside the island enters only when the view changes. Pressing a pill or a minute button on the same view doesn’t flash it.
  - When the question window moves to its next state it doesn’t pop in again; it slides in place, and only new rows fade in (0.18 seconds).
- App (Coucou’s values):
  - The island grows on a spring (0.5 seconds, damping 0.72) and shrinks on a curve (0.45, 0, 0.2, 1, 0.34 seconds).
  - Content fades out first in 0.16 seconds and comes back 0.16 seconds later on a spring (0.4 seconds, damping 0.8). The same when switching tabs.
  - Pills and buttons grow to 1.04× and brighten under the pointer, and press to 0.94×.
  - The mascot moves only when changing places, following the pointer with its eyes, blinking, changing expression, and when pressed.
  - The record bars grow once when the tab opens.
- Sounds: quiet macOS system sounds only. Peek and open Pop, tabs and pills Tink, a pat Bottle, session start Hero, session end and break end Glass. Sounds can be turned off.
- Follow `prefers-reduced-motion` and the Mac’s "Reduce motion".

## Iteration Guide

1. Before making a new screen, decide what its primary button is.
2. Don’t add colours. If you need one that isn’t in the tables above, change this document first.
3. After writing the words, cut them once.
4. After changing an app screen, render it with `StudyNotch --render <folder>` and look.

## Known Gaps

- The mascot has no name.
- The mascot's sad and cross moods aren't tied to anything that happens yet.
- The sounds are borrowed Mac system sounds. There are no sounds of our own yet.
- The app has no light theme. The island is always black, so it doesn’t need one.
- The name "StudyNotch" is temporary.
