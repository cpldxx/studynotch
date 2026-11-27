# Development

A Swift package with no outside libraries, and a static site with no build step. `CLAUDE.md` holds the project’s rules; read it before changing anything.

## Build and run

```bash
./scripts/build.sh && open build/StudyNotch.app
```

The build is signed with a Developer ID or Apple Development certificate when the Mac has one, so the Accessibility and Screen Recording permissions survive a rebuild. Without one it is signed ad hoc, and they have to be granted again after every rebuild. Set `STUDYNOTCH_SIGN_IDENTITY` to pick a certificate.

## Checks

| Command | What it checks | Uses your AI account |
|---|---|---|
| `swift build && .build/debug/StudyNotch --selftest` | Pure logic: drift rules, finding pages in PDFs, settings, parsing each AI’s output, sign-in states, course folders, the mascot’s look | No |
| `.build/debug/StudyNotch --uitest-courses` | Clicks through the Add tab in the real window: picking, Add, closing without Add, Edit, linking, renaming, removing | No |
| `.build/debug/StudyNotch --uitest-graph` | Clicks the Graph button on a course's card in the real window, then a theorem in the course window: its page and its links come up | No |
| `.build/debug/StudyNotch --answertest` | Draws sample answers in the real web view and reads back what it shows: math is typeset, prices are not, HTML in an answer is shown as text and never run. Needs the internet for the math and Markdown libraries | No |
| `.build/debug/StudyNotch --uitest-eyes` | How far the mascot’s eyes move with the pointer, measured in the real window | No |
| `.build/debug/StudyNotch --uitest` | The AI card and the Add tab in the real window, including one real question each to Claude and ChatGPT | Yes |
| `.build/debug/StudyNotch --asktest [image]` | One real question, as the app sends it. `STUDYNOTCH_AI=codex-cli` picks ChatGPT | Yes |
| `.build/debug/StudyNotch --asktest-claude-app` | The real question flow with Claude: a question and a follow-up kept as one named session in the course’s folder, and the Claude app taking it (its log). Leaves one “STUDYNOTCH TEST” session in the Claude app | Yes |
| `.build/debug/StudyNotch --asktest-memory` | A real question with Claude in a course that already has a memory line and a quiz: the answer has to quote the earlier question and name the quiz. Not kept in the Claude app | Yes |
| `.build/debug/StudyNotch --asktest-profile` | Writes a course's profile for real with Claude from an outline, a quiz and a midterm: the grading, the midterm's date and what comes up most, each with its file and page | Yes |
| `.build/debug/StudyNotch --asktest-course` | A real question the AI can only answer by opening the course’s files itself | Yes |
| `.build/debug/StudyNotch --render <folder>` | A picture of every island and question-window state, to look at | No |
| `.build/debug/StudyNotch --render-site site/assets/img/app` | The same pictures on a transparent background, for the site and this README | No |

The `--uitest` modes run the real app in a throw-away home folder, so your settings, courses and sign-ins are not touched and nothing goes to your Trash.

After changing the site, check that it opens with no server (`open site/index.html`), that nothing scrolls sideways at 390px, and that it is complete with Reduce motion on. To preview it with a server:

```bash
python3 -m http.server 4173 --directory site
```

## Deploying the site

The site is on Cloudflare Pages as the project `studynotch`: [studynotch.pages.dev](https://studynotch.pages.dev). It is the `site/` folder as it is; `site/_headers` sets its security headers. Commit first, then:

```bash
npx --yes wrangler@4 pages deploy site --project-name studynotch --branch main --commit-hash "$(git rev-parse HEAD)" --commit-message "$(git log -1 --format=%s)"
```

Signing in to Cloudflare (`npx wrangler@4 login`) is done by the owner of the account.

## Layout

| Path | What it is |
|---|---|
| `Sources/StudyNotch/AppModel.swift` | State and every action: sessions, drift cards, the question flow, courses, AI connection |
| `Sources/StudyNotch/IslandPanel.swift` | The window over the notch: the notch’s size, which screen, which clicks reach the island, the pointer for the mascot’s eyes |
| `Sources/StudyNotch/IslandScreens.swift` | The island’s screens: peek, tabs, cards, course pills, record, add and edit, drift card, summary, setup |
| `Sources/StudyNotch/IslandViews.swift` | The island’s shape, motion values, colour tokens and shared buttons |
| `Sources/StudyNotch/Mascot.swift`, `MascotRenderer.swift` | Squat: its moods, blinks, pointer following, and the Metal shader that draws it |
| `Sources/StudyNotch/PopupPanel.swift`, `AnswerWebView.swift` | The question window, and answers drawn as Markdown with math |
| `Sources/StudyNotch/RightClickWatcher.swift`, `SelectionWatcher.swift` | The button above the right-click menu, and reading the selected text |
| `Sources/StudyNotch/ScreenshotWatcher.swift`, `FocusWatcher.swift` | New screenshots and captures; the front app, window and tab, and the drift rules |
| `Sources/StudyNotch/Materials.swift` | Course folders, linked folders, reading PDFs, finding the page of a sentence, the text copies an AI may open |
| `Sources/StudyNotch/CourseGraph.swift`, `CourseWindow.swift` | A course's graph: definitions, theorems and examples read from its notes and which use which; the window that shows it, a picked item's page, the course's profile and its files by kind |
| `Sources/StudyNotch/ClaudeApp.swift` | Handing questions kept as Claude Code sessions to the Claude app with its own `claude://resume` link |
| `Sources/StudyNotch/AIEngine.swift`, `Prompts.swift` | Claude, ChatGPT (Codex), Gemini (`agy`) and the API key; sign-in checks; what is sent and the rules given to the AI |
| `Sources/StudyNotch/Config.swift`, `SessionLog.swift` | The settings file and session history |
| `Sources/StudyNotch/DevTools.swift`, `UITest.swift` | Self-tests, real-question tests, renders, and the click-through tests |
| `site/` | The landing page and docs. `assets/squat.js` draws the mascot with the same shader in WebGL |
| `design/` | Mascot drafts and rounds. Not part of the site |
| `docs/assets/` | Pictures for this README |

## Where your data lives

```
~/StudyNotch/
├── config.json          courses, linked folders, the connected AI, drift rules
├── sessions.jsonl       finished sessions
├── Captures/            captures attached to questions (deleted after a week)
├── .accounts/           sign-ins kept only for StudyNotch (“Another account”)
├── .cache/text/         the read text of PDFs in linked folders
└── Courses/<course>/
    ├── course.md        course notes, sent in front of every question
    ├── materials/       PDFs copied into the course, one folder per kind (Lecture notes, Quizzes, Exams, …)
    ├── text/            every PDF of the course as text, page by page: what the AI may open
    ├── memory.md        a line per question asked in the course; the latest go with each question
    ├── profile.md       how the course is graded and tested, written by the AI when you ask
    ├── cards.md         review cards
    └── log/             questions and answers by date
```

Questions asked with Claude are also kept by Claude Code itself, in `~/.claude/projects/<the course folder>/<session>.jsonl`, which is what the Claude app shows. API keys live only in the Keychain.

## config.json

- `presets`: the courses. Each has `course`, `allow` (places allowed only in that course) and `folders` (linked folders). Edit them on the Add tab rather than here.
- `ai.provider`: the connected AI (`claude-cli`, `codex-cli`, `gemini-cli`, `api-key`), or empty for none. `ai.account` is `mac` or `own` (another account). `ai.model` is empty for each AI’s default. `ai.keepInClaude` (on by default) keeps each Claude question as a Claude Code session in the course’s folder and hands it to the Claude app; it only applies to Claude with the Mac’s account.
- `sessionMinutes`, `breakMinutes`: session and break length.
- `allowAlways`, `distractions`: an entry with a dot is a site; one without is an app name.
- `nudgeAfterSeconds`: time on a distracting place before a drift card. Default 60.
- `offerOutsideSession`: whether a screenshot opens the question window outside a session too. Off by default.
- `sounds`: small macOS system sounds. On by default.
- `display`: `notch` (default), `main` (the menu bar screen) or `mouse` (the screen with the pointer).

After editing by hand, choose Reload settings in the menu bar icon.
