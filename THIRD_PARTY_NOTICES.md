# Taken from other projects

## Coucou

https://github.com/Louis-CFM/coucou

StudyNotch’s notch island follows Coucou’s approach. What was taken:

- The spring used when the island grows, the curve used when it shrinks, and the timing of content fading out and in
- The "ear" shape where the folded island’s top corners flow into the screen edge
- Reading the mouse position continuously so clicks outside the island pass through
- The combination of options for running a signed-in Claude Code and Codex read-only
- The small 80×24 bar used instead of a notch on screens without one, and not catching clicks just below that bar
- How the island’s screen is chosen: by default the screen with a notch (or the menu bar screen if none has one), otherwise the menu bar screen or the screen with the pointer
- The island’s sizes and flow: hidden (notch size), a peek with 80pt ears on both sides when pointed at, a 640pt card that opens when clicked, folding by itself 15 seconds after the pointer leaves, with a countdown line in the last 10 seconds
- The open island’s layout: tabs (pills) on the left and icons on the right of the strip beside the notch, a left card and a grid of pills on the right, the card colour (#141518) and the colour glowing up from the bottom, pills growing and glowing under the pointer, and the overlapping transition between tabs
- A character moving on a spring to a fixed place for each state inside the island (the folded island’s left ear, the left of the open card), and a soft glow in the state colour behind it
- A one-line summary appearing under the folded island when pointed at, the island opening briefly to say hello at launch and then folding, and the add view opening when a file is dragged over
- Parts of the chat view: a pill showing which AI answers, my message as a bubble on the right, three dots swelling in turn, a status line with a light sweeping across it, and a text field with the send button inside it

Not taken: the names Coucou and Mochi, the Mochi character (its shape, expressions and movement as a character), the app icon, the sounds, and the introduction video and images.
These belong to the original author and are outside the licence below. Sounds are the system sounds that come with macOS.

Where Mochi sat in Coucou, StudyNotch has its own mascot (a sheet of paper with a folded corner).
The mascot was drawn new for StudyNotch and is not based on Mochi’s shape or drawing code.
Its expressions (focus, drift, break, thinking, glad, session done) and reactions (a hop, a short line) are StudyNotch’s own too.

Coucou’s code is published under the MIT licence below.

```
MIT License

Copyright (c) 2026 Louis Raillé

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
