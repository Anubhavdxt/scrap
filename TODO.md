# scrap TODO

v1 plan (Mac only, free, Markdown files, Swift/SwiftUI + AppKit). Work on feature branches, squash-merge PRs.

## v1 milestones
- [x] 1. Setup: SwiftPM package, Makefile app bundle, README, MIT license, repo hardening, CI
- [x] 2. Core editor: pads as `.md` files, autosave, file watching (#2)
- [x] 3. Pads: new, rename, trash, ⌘K quick-switch palette (#4)
- [x] 4. Markdown highlighting, 18 ported themes (#5)
- [x] 5. Global hotkey (⌃⌥Space) and menu bar item (#6)
- [x] 6. CLI: `scrap add "…"` (argument or stdin), shares config with the app (#7)
- [x] 6c. Popover attached to the menu bar icon (Tot-style): coloured pad dots, themed settings popover attached to the gear, window size in columns × rows
- [x] 6b. Fixed pads (default 7, configurable 1 to 99, ⌘1–9, clear instead of delete); CLI `add` fills the last empty pad, else appends to the last
- [x] 7. Sync conflicts: keep both versions (conflict copies like `3 2.md` merge into the pad, originals archived in `.conflicts/`)
- [x] 8. Release: Homebrew tap in this repo (`Formula/scrap.rb`), `make install`, README (v0.1.0 released)

- [x] Logo: app icon, menu bar icon, README header, social preview (`make icons`)

## Later / ideas
- [ ] Detach/pin the popover into a normal window
- [x] Configurable hotkey and pad folder (settings UI + shared config file for the CLI)
- [ ] Optional "say hi" screen; opt-in anonymous ping only after v1
- [x] Launch at login
- [ ] Per-language highlighting for fenced code (currently a generic lexer)
- [ ] Tests for the app target (EditorModel) and a manual QA checklist

## Housekeeping
- [ ] Verify conflict handling on two real Macs (iCloud's conflict file naming is assumed, see ConflictResolver)
- [ ] Add a bypass for the repo owner to the `protect-main` ruleset (owner does this in Settings)
- [ ] Confirm CodeQL results in the Security tab
- [ ] Optional: one-time import of old named pads (idea.md etc.) into numbered slots
- [ ] Check the name `scrap` for Homebrew and domain availability
