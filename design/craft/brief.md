# Mascot brief (craft round, 2026-11-19)

Earlier drafts were judged "obviously vibe-coded": one recipe (glossy radial gradients, dot eyes, blush,
looping breathe/blink/float) with only the subject swapped. This round changes the process, not the subject:
silhouettes first, numbers before drawing, a separate 20 px master, size-ladder checks, three passes at most.

## Personality

Calm, a little dry, never gushing. A quiet study partner that keeps your place. It reacts to what you are
doing, not to the mouse.

## Words from the user

Academic, premium, alive (a creature, not an object with a face stuck on), Apple-like, casual.

## Banned

- Radial gloss, highlight blobs, glows and halos. Gradients that rescue a weak form.
- Default blush on the cheeks. Sparkles. "ω" mouths.
- Loops that run regardless of state (fixed breathe, fixed blink, float).
- Owls (Duolingo), squircle bodies with big white eyes (Mochi), eyes that follow the cursor, poke-to-annoy reactions,
  food or dessert names.
- Round symmetric blob bodies. A silhouette that is a circle or a rounded square.
- More than three colours in one master. Hairlines or details under 1.5 px at 20 px.

## Hard rules

- Colours only from DESIGN.md: Paper #FFFFFF, Desk #EDF0F3, Ink #14233B, Graphite #566173,
  Highlighter #FFE94A, Island #000000. Shade with Ink at low opacity, not new colours.
- One light, from the top left. Two tones per surface (lit, shadow) before anything else.
- The 20 px master is drawn on its own grid (40 physical px at 2x), flat, one or two colours, one facial feature.
- The large master uses the same construction in a quarter turn, with crisp edges.
- Five states are number changes on one drawing: idle, focus, writing an answer, drift, break.
- Each state must read from the silhouette alone at 20 px, before the face is added.
- Every candidate is checked at 20 pt next to a squircle-with-big-eyes stand-in for Mochi.

## Process

1. 36 black silhouettes in six families; pick three that differ in structure.
2. A construction sheet per pick (primitives, radii, angles, colours, state numbers).
3. Two masters per pick: 20 px and large.
4. Checks: 16/20/32/64/512 px on light and black, one colour, squint blur, the Mochi stand-in, svg_audit.py
   (logo-design-skill) and path_audit.py (draw-better-svg). Fix the single worst failure per pass, stop after three.
