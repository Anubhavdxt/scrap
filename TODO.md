# scrap TODO

v1 plan (Mac only, free, Markdown files, Swift/SwiftUI + AppKit). Work on feature branches, squash-merge PRs.

## v1 milestones
- [x] 1. Setup: SwiftPM package, Makefile app bundle, README, MIT license, repo hardening, CI
- [x] 2. Core editor: pads as `.md` files, autosave, file watching (#2)
- [x] 3. Pads: new, rename, trash, ⌘K quick-switch palette (#4)
- [x] 4. Markdown highlighting, 18 ported themes (#5)
- [x] 5. Global hotkey (⌃⌥Space) and menu bar item (#6)
- [x] 6. CLI: `scrap add "…"` (argument or stdin), shares folder config with the app
- [ ] 7. Sync conflicts: keep both versions when iCloud produces conflicting files
- [ ] 8. Release: Homebrew tap (build from source), `make install`, README polish

## Later / ideas
- [ ] Configurable hotkey and pad folder (settings UI + shared config file for the CLI)
- [ ] Optional "say hi" screen; opt-in anonymous ping only after v1
- [ ] Launch at login; option to hide Dock icon
- [ ] Per-language highlighting for fenced code (currently a generic lexer)
- [ ] Tests for the app target (EditorModel) and a manual QA checklist

## Housekeeping
- [ ] Add a bypass for the repo owner to the `protect-main` ruleset (owner does this in Settings)
- [ ] Confirm CodeQL results in the Security tab
- [ ] Check the name `scrap` for Homebrew and domain availability
