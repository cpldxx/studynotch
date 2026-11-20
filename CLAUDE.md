# StudyNotch: a guide for AI helpers

A study helper that lives in the Mac’s notch. No server: it runs only on the Mac. `StudyNotch` is a working name.

## What is where

- `Sources/StudyNotch/`: the Mac app (Swift, SwiftUI + AppKit, SwiftPM). The role of each file is in the "Code layout" table in `site/docs/build-log.html`. The island screens are in `IslandScreens.swift`; shared shapes and colours in `IslandViews.swift`.
- `DESIGN.md`: colours, type, spacing and button rules. Read it before changing a screen.
- `site/`: the landing page and docs. Static HTML with no build tools. `site/assets/styles.css` is all the styling. The first page’s motion is in `assets/squat.js` (draws the mascot in 3D with WebGL), `assets/mascot.js` (moves it) and `assets/demo.js` (the Mac screen, the seven-step tour, the mood stage).
- `design/`: mascot candidate drafts, gathered in `design/index.html`; the chosen mascot's source drawing and its rounds are in `design/craft/` (`squat.html`). Not part of the site.
- `scripts/build.sh`: builds and signs the app. `scripts/make-icon.swift`: the app icon.
- App data lives in `~/StudyNotch/` (config.json, sessions.jsonl, Courses/, Captures/).

## Repository

- GitHub: `cpldxx/studynotch`, branch `main`. Set up the way the user's `catchbunny` repo is (2026-11-20): a short README with pictures, the long account in `site/docs/` and `docs/`.
- The user asked for the README and the repo to be kept up to date. After a change: make `README.md` and `docs/development.md` still true (commands, test counts only if they are quoted, screenshots in `docs/assets/` or `site/assets/img/app/`), then commit and push to `main`.
- Commits read like catchbunny's: one change per commit, the subject a plain sentence about what changed for the user (no `feat:` prefixes), a body that says what and why in the project's own words. No co-author or attribution lines.
- Never commit `.build/`, `build/`, anything from `~/StudyNotch`, sign-ins, keys or the user's own course files. README pictures use the example courses (MATH 237, STAT 230, ACTSCI 221) and example accounts only.
- The repo's visibility is the user's call; don't change it without being asked.
- The site is deployed on Cloudflare Pages, project `studynotch`, at https://studynotch.pages.dev (first deployed 2026-11-20 at the user's request). The command is in `docs/development.md`. Deploy only committed work, and only when the user asks for it; after a deploy, open the live pages and check them (status, pictures, console, headers). The Cloudflare sign-in is the user's.

## Build and check

```
swift build && .build/debug/StudyNotch --selftest
./scripts/build.sh && open build/StudyNotch.app
.build/debug/StudyNotch --render <folder>          # a picture of every state (grey background)
.build/debug/StudyNotch --render-site site/assets/img/app   # transparent pictures for the site
.build/debug/StudyNotch --asktest [image path]               # one real question (uses the user's account); STUDYNOTCH_AI=codex-cli picks ChatGPT
.build/debug/StudyNotch --uitest                             # clicks through the AI card and the Add tab in the real window; sends 2 real questions
.build/debug/StudyNotch --uitest-courses                     # only the Add tab (no question is sent)
.build/debug/StudyNotch --asktest-course                     # real question the AI can only answer by opening the course's files
.build/debug/StudyNotch --uitest-eyes                        # how far the eyes move with the pointer, in the real window
```

Site preview: `python3 -m http.server 4173 --directory site`, or with no server `open site/index.html` (every path is relative).

## Rules

- No server. The only network requests are questions to the AI the user connected.
- No keyboard shortcuts. Everything is done by clicking.
- A question starts from the button that appears above the right-click menu; the user picks a preset and presses "Send". The answer appears in the question window, not the notch.
- A session is picked by course name. Courses don’t have separate "tasks".
- Course files (user's request, 2026-11-19). A course reads PDFs from two places: copies in its own `materials` folder, and folders linked to it (`Preset.folders`), which are read where they are and never copied or written to (their read text is cached in `~/StudyNotch/.cache/text`). The Add tab has two pages. New course: PDFs and folders dropped on the island or picked with "Link folder" / "Add PDFs" only wait in a list (`AppModel.staged`); "Add" makes the course, links the folders and copies the PDFs; closing the page without "Add" forgets them and makes nothing. Existing course ("Edit" on its Home card): link or unlink folders, add PDFs, ✕ a copied PDF (it goes to the Trash), rename, and "Remove course" (asks first; its own folder goes to the Trash, linked folders are only unlinked). Nothing is ever deleted outright. An outside click doesn't fold the Add tab, because files are dragged in from other apps.
- Never show Claude on screen. Run the Claude Code inside the Claude app in the background and take only the answer. Don’t drive or scrape the Claude app’s windows.
- AI choices (user's request, 2026-11-19): Claude (the Claude Code inside the Claude app), ChatGPT (the Codex inside the ChatGPT app), Gemini (Google's Antigravity CLI, `agy`) or an Anthropic API key. Google's old `gemini` command stopped serving personal Google accounts on 2026-06-18, so Gemini goes through `agy` (installed with `brew install --cask antigravity-cli`). The app checks each sign-in (`AIEngine.refreshStatus`: `claude auth status`, `codex login status`, `agy models`, because `agy` keeps its sign-in in the macOS Keychain; signed out it only prints "Please sign in" and opens nothing). Status checks never send a question. Gemini answers haven't been tried with a real account.
- Only the AI the user connected answers (user's request, 2026-11-19, after ChatGPT answered without them meaning to connect it). Signed in on this Mac (the ChatGPT or Claude app) is not connected: the tile says "Signed in on this Mac" and clicking it asks "Connect …?" with the account (Claude's email) before `config.ai.provider` is set. No "Auto", and no falling back to another AI when the connected one signs out (`AIEngine.resolve`); the question window says so instead. Empty provider = nothing connected.
- Accounts (user's request, 2026-11-19): each tile shows the account it would use (Claude: `claude auth status`; ChatGPT: the email and plan in Codex's `auth.json` ID token; shown on screen, never logged). "Another account" and every sign-in started from StudyNotch go to a sign-in kept only for StudyNotch in `~/StudyNotch/.accounts/` (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`; `config.ai.account` = "own"), so the Claude and ChatGPT apps are never signed in or out by us. Disconnecting an "own" account signs it out. Gemini's `agy` has one sign-in for the Mac. "Test connection" sends one real question, only when pressed.
- Be honest about where questions go: the same account and plan, through Claude Code / Codex, not the chat window. They don't appear in the claude.ai / ChatGPT chat lists, chat Projects aren't used, and the tools are told not to save the conversation (`--no-session-persistence`, `--ephemeral`). Never claim otherwise in the app or the docs.
- The first launch starts with connecting the AI (user's request, 2026-11-19): the setup card's step 1 shows Claude, ChatGPT and Gemini as tiles, each saying what it needs (connected, signed in on this Mac, sign in, get the app, install); step 2 is Accessibility and Screen Recording. Clicking a tile does the next thing: asks to connect it, opens its own sign-in in a Terminal window (`AppModel.signIn`), installs Gemini's `agy` with Homebrew, or opens the Claude or ChatGPT download page. While a window is open the card checks every three seconds and connects the AI when its sign-in is done, since the user started it from that tile (`AppModel.waitingFor`). The menu bar only opens this card; it doesn't pick an AI itself. If nothing can answer at launch, the card opens at step 1 again. StudyNotch never sees a password.
- A course is the connected AI's project (user's request, 2026-11-19). Chat Projects on claude.ai / chatgpt.com / Gemini have no way in for another app, so don't promise them; each AI's own tool treats a folder as a project instead. `CourseStore.syncText` keeps `<course>/text/` (one .txt per PDF, own and linked, with `=== <file>, page <n> ===` before each page) and the AI is started there: Claude with `--tools Read,Glob,Grep` and `--add-dir <course>/materials` (it is refused anything outside; no `--allowedTools`), Codex with `-C` (read-only sandbox), `agy` with `--add-dir`. Never hand over a linked folder itself (it may hold private files), never write into one, never give a writing or shell tool. The API key gets the matching page only. `--asktest-course` proves it with a real question whose answer is not in the excerpt (passes for Claude and ChatGPT; Gemini untried). Everyday questions must still be answered from the excerpt without opening files (`STUDYNOTCH_PLAIN=1`).
- Never send an empty question: with no picked text, capture, typed words or earlier answer, the question window says what is missing (usually Accessibility) instead.
- A new install has one course, General. Don't seed sample courses.
- Don’t block drifting; tell the user with a card. Never store or send which apps and sites were visited.
- Never write selected text, answers or window titles to `debug.log`.
- API keys live only in the Keychain.
- Don’t add external libraries.
- Don’t add colours. If one is needed, change `DESIGN.md` first. The app is white and grey on black (the user's call, 2026-11-19): white marks the primary button, picked text and progress. Its one spoonful of colour is a faint state-coloured light behind cards, the question window and the mascot; never a fill, dot, border or text. The website follows the mascot too (the user's call, 2026-11-20): it is the mascot's studio, a softly lit black with white type and round shapes, and has no yellow or other accent (DESIGN.md). Courses have no colours.
- No testimonials, user counts or logo strips that don’t exist on the site. Facts only. The first page’s Mac screen is a demo; never remove the note that its numbers and answers are examples.
- Everything is in English: the site (since 2026-11-18) and the app (since 2026-11-19). The app’s labels match the site demo’s, and the docs quote them as they appear. Answers follow the language typed with each question (Hangul → Korean, otherwise English; `Prompts.answerLanguage`). A button pressed on its own is English, because its label is; the user chose this over a language menu (2026-11-19). The old `ai.language` key is ignored on purpose, and the old Korean course name "일반" is read as "General" (`AppConfig.renamed`).
- English is longer than Korean: after changing any words in the app, render every state and check nothing is cut off or wrapped.
- After changing the site, check that it still opens with no server (`open site/index.html`), that nothing scrolls sideways at phone width (390px), and that the still screen is complete with "Reduce motion" on.
- The island’s flow is Coucou’s: hidden → point at it to peek (80pt ears on both sides) → click to open (640pt, tabs and cards) → folds by itself 15 seconds after the pointer leaves. Clicking outside folds it at once. Sizes and the mascot’s places are decided in one place: `AppModel.size(for:geo:)` and `mascotSpot(for:geo:)`.
- On a screen without a notch, the mascot sits in an 80×24 bar in the middle of the menu bar. Never draw a big black shape pretending to be a notch. The default screen for the island is the one with a notch.
- The mascot is Squat (since 2026-11-19): a round body of glossy black (no feet) with two white painted eyes that follow the pointer. It is drawn new by us and lives anywhere in the island. It is rendered in 3D by code from one shader: Metal in the app (`MascotRenderer.swift`, used by `Mascot.swift`), WebGL on the web (`site/assets/squat.js`). Change both shaders together. Don’t replace it with image files or an external 3D library. Following the pointer: the eyes slide toward it and the body turns toward it (`MascotView.aimed`, the same numbers in `site/assets/mascot.js`). The shader's turn is positive to the left as seen from the camera, so the turn is the negative of the pointer's x; with the same sign the two cancelled and the eyes barely moved (fixed 2026-11-19, measured with `--eyes-sweep` and `--uitest-eyes`). The user chose the round body, white eyes and pointer-following eyes knowing they are close to Coucou's Mochi; don't add more of Mochi (no squircle, no poke-to-annoy, no wardrobe, never its name or art). The rules are under "Mascot" in `DESIGN.md`; the user tuned the eyes by hand (sizes, the long tapered smile), so keep those numbers.
- Sounds are macOS system sounds only, and `config.sounds` must be able to turn them off.
- The notch island’s shape and motion follow Coucou (MIT). Write down what was taken in `THIRD_PARTY_NOTICES.md`. Never take the names Coucou and Mochi, or its character, icon or sounds.
- After changing an app screen, render it with `--render` and look, and re-render the site’s pictures with `--render-site`.
- After changing pure logic (rules, parsing, page finding), add a check to `DevTools.selfTest`.

## Not checked yet

The AI connection card's and the Add tab's buttons are clicked for real by `--uitest` (mouse events into the real window, 26 + 15 checks, 2026-11-19); a real drag from Finder and the real Open panel are not (the test hands the files over directly). Signing in with another account to the end (it needs the user's password), a Gemini answer, other real mouse clicks, whether the button appears in place above the right-click menu, reading selected text in Preview, Chrome and Safari, and noticing screenshots.
AI answers were checked with `--asktest` for both text and images. When changing these parts, first ask the user how it went when they tried it.
