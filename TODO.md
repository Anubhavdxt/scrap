# scrap TODO

v1 plan (Mac only, free, Markdown files, Swift/SwiftUI + AppKit). Work on feature branches, squash-merge PRs.

## v1 milestones
- [x] 1. Setup: SwiftPM package, Makefile app bundle, README, MIT license, repo hardening, CI
- [x] 2. Core editor: pads as `.md` files, autosave, file watching (#2)
- [x] 3. Pads: new, rename, trash, ⌘K quick-switch palette (#4; now search across all pads)
- [x] 4. Markdown highlighting, 18 ported themes (#5)
- [x] 5. Global hotkey (⌃⌥Space) and menu bar item (#6)
- [x] 6. CLI: `scrap add "…"` (argument or stdin), shares config with the app (#7)
- [x] 6c. Popover attached to the menu bar icon (Tot-style): coloured pad dots, themed settings popover attached to the gear, window size in columns × rows
- [x] 6b. Fixed pads (default 7, configurable 1 to 99, ⌘1–9, clear instead of delete); CLI `add` fills the last empty pad, else appends to the last
- [x] 7. Sync conflicts: keep both versions (conflict copies like `3 2.md` merge into the pad, originals archived in `.conflicts/`)
- [x] 8. Release: Homebrew tap in this repo (`Formula/scrap.rb`), `make install`, README (v0.1.0 released)

- [x] Logo: app icon, menu bar icon, README header, social preview (`make icons`)

## Later / ideas
- [x] Rendered vs raw toggle (eye button, ⌥⌘R; raw = same colours, marks visible); proportional prose font option with monospaced code; selection in the pad's colour with selection counts
- [x] Smart bullets (○ ● □ ■ ▷ ▶ ☆ ★ …) as clickable characters, and the `*` symbol picker (bullets, dividers, checkmarks, arrows, numbers, technical)
- [x] Custom smart bullets (your own open/done pairs, up to eight)
- [x] Formatting commands (⌘B ⌘I ⇧⌘X ⌘E ⌃- ⌃8), keep indentation on Return
- [x] Clickable task icons and bullet dots, link styling (pasted URLs too) with ⌘-click to open
- [x] Live Markdown rendering: real bold/italic/strikethrough, sized headings, code panels, dimmed or hidden markers, colour highlights for bold and links (toggle)
- [x] Decided against bundling highlight.js (measured: +73 KB, +6 MB RAM when used, slower than the Swift lexers, vendored JS to maintain). Improve the Swift lexers instead if any language's colours look worse than the portfolio
- [x] From Tot's settings: menu bar icon tinted with the pad's colour, "Esc closes window" toggle, footer with task/format/share buttons and a "saved just now" indicator
- [x] Hotkey opens the detached window at the pointer
- [x] `scrap://` links: open a pad, add text (never read)
- [x] From Tot's settings: pad number in its dot, alternate app icons (Dock)
- [ ] Vibrant background
- [x] Font size (⌘+ ⌘− ⌘0), font family picker, line wrapping toggle
- [x] List helpers: Return continues lists, Tab indents, ⌘Return toggles checkboxes
- [x] Detach/pin the popover into a normal window (pin button, remembers size and place, optional always-on-top)
- [x] Icon visibility: menu bar / Dock / both (Dock-only always uses the window)
- [x] Configurable hotkey and pad folder (settings UI + shared config file for the CLI)
- [x] Optional first-launch "say hi" screen (name, email, suggestions); saved locally in `~/Library/Application Support/scrap/hello.json`, nothing is sent
- [ ] Backend for say-hi entries (e.g. Supabase table + insert-only policy); must ask for consent again before uploading anything already saved, then flip `sentToServer`
- [ ] Opt-in anonymous ping only after the above
- [x] Launch at login
- [x] Per-language highlighting for fenced code (`CodeLanguage`, 18 language families; unknown languages use a generic lexer)
- [x] Tests for the app target (EditorModel, 15 tests) and a manual QA checklist (`docs/QA.md`)

## Next (after v0.2.0)
- [x] Search results show the text around each match (not just a pad label)
- [ ] Performance (baseline measured at v0.2.0, release build, fresh launch, nothing open):
  - Memory: footprint 25 MB (what Activity Monitor shows; `ps` RSS says 115 MB but counts shared system libraries). 18 MB of it is malloc. Tot, after 15 days of use, has a 269 MB footprint (not comparable: needs scrap measured after long use).
  - CPU: 0% idle.
  - Typing cost: every edit re-parses and restyles the whole pad. Warm, release: 2 KB 6 ms, 10 KB 32 ms, 50 KB 175 ms, 100 KB about 380 ms (styling is about 85% of it; parsing is cheap). Highlighting stops at 300 KB.
  - Done: restyle only what an edit touches (#51): a keystroke in a 100 KB pad went from about 380 ms to about 42 ms, the rest being the parse.
  - Done: footprint after use: window with a 200 KB pad about 64 MB; 40 open/close cycles of the editor, settings and search views and 300 pad switches show no growth (no leaks); search reads the pads once per opening, not per keystroke.
  - Decided against `-Osize`: 9% smaller binary (2.94 to 2.66 MB), no memory gain, risks slower highlighting.
  - To do: parse incrementally too (the remaining 35 ms of a keystroke in a 100 KB pad); a CI benchmark with a budget.
- [ ] README demo GIF, screenshots, repo topics/description, comparison line, CONTRIBUTING + issue templates, "good first issue" labels
- [ ] Prebuilt notarized .zip (needs a paid Apple Developer account: decide)
- [ ] Launch posts (owner): Show HN, r/macapps, r/swift, r/opensource, Product Hunt, awesome-macos lists

## Housekeeping
- [ ] Verify conflict handling on two real Macs (iCloud's conflict file naming is assumed, see ConflictResolver)
- [ ] Add a bypass for the repo owner to the `protect-main` ruleset (owner does this in Settings)
- [ ] Confirm CodeQL results in the Security tab
- [ ] Optional: one-time import of old named pads (idea.md etc.) into numbered slots
- [ ] Check the name `scrap` for Homebrew and domain availability
