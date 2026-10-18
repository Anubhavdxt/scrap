# Manual QA checklist

`swift test` covers the logic (pads, config, conflicts, list editing, the editor model). These checks cover what only
a human at a real Mac can see. Run them before a release, with a freshly built app:

    make app && open build/Scrap.app

Tip: to see the first-launch card again, run `defaults delete dev.anubhav.scrap sayHiDone`.
Do not run `sudo make`: it leaves root-owned files in `build/` that break the next build.

## Install
- [ ] `brew tap Anubhavdxt/scrap https://github.com/Anubhavdxt/scrap && brew install scrap` builds and installs
- [ ] `scrap link` links the app into /Applications and `open -a Scrap` launches it, with no Gatekeeper warning
- [ ] `scrap --version` matches the release; `brew test scrap` passes
- [ ] `scrap unlink` removes only the link (and refuses to touch a real `Scrap.app`)

## Menu bar and popover
- [ ] The menu bar icon is the scrap logo and tints correctly in light and dark menu bars; there is no Dock icon
- [ ] Click the icon: the popover drops down from it and you can type immediately
- [ ] ⌃⌥Space shows and hides it from any app
- [ ] Clicking outside closes it; switching apps closes it; text typed just before closing is saved
- [ ] Right-click the icon: Settings… and Quit work
- [ ] Opens at the size set in Settings > Window (columns × rows) and resizes live when it changes

## Editor
- [ ] ⌘C, ⌘X, ⌘V, ⌘A, ⌘Z and ⇧⌘Z work
- [ ] Markdown is highlighted (headings, bold, italic, code, links, quotes, lists, fenced code) in a few themes, dark and light
- [ ] Lists: Return continues, an empty item ends the list, Return mid-list renumbers, Tab/⇧Tab indent, ⌘Return toggles a checkbox, ⌘Z undoes each in one step
- [ ] ⌘+ ⌘− ⌘0 change the font size; View > Wrap Lines toggles wrapping; the font family picker changes the font
- [ ] Very large text (a few hundred KB) stays responsive

## Pads
- [ ] The dots at the top: current is filled, pads with content show a centre dot, hovering shows a preview; clicking switches
- [ ] ⌘1–⌘9 jump to pads; ⌘K opens the palette (type to filter, ↑↓, Return, Esc)
- [ ] ⇧⌘⌫ clears the pad after a confirmation (and Esc cancels it)
- [ ] Changing the pad count in Settings hides and restores pads without losing text

## Settings
- [ ] The gear opens an attached settings popover and both stay open together
- [ ] Clicking in the editor closes settings only; clicking outside closes both; Esc closes settings first, then the editor
- [ ] Tabs: Appearance, General, Window, Shortcuts, About; the last tab is remembered; ⌃Tab cycles
- [ ] The pane follows the selected theme and re-themes when the theme or Auto/Light/Dark changes
- [ ] Recording a new global shortcut works; a taken one shows an error and keeps the old one; Reset works
- [ ] Choosing another pad folder switches pads; "Use default" goes back; old files stay put
- [ ] "Open scrap at login" registers (approve it in System Settings if asked)

## Say hi
- [ ] The first-launch card appears once, fields get focus, a bad email is flagged, Skip and Esc dismiss it
- [ ] "Say hi" saves to `~/Library/Application Support/scrap/hello.json` and says nothing was sent
- [ ] The Discussions, idea and star links open the right GitHub pages; About > Say hi… reopens the card

## Files, CLI and sync
- [ ] Editing a pad file in another editor reloads in the app (unless you have unsaved typing)
- [ ] `scrap add "x"` fills the last empty pad, `scrap add -p 2` targets pad 2, `scrap show 2` and `scrap list` work
- [ ] The CLI and the app agree on the folder and pad count (`~/.config/scrap/config.json`)
- [ ] Two Macs: edit the same pad on both while offline, then reconnect. A `3 2.md` style copy is merged into the pad under a
      "conflicting version from sync" line, the copy moves to `.conflicts/`, and a notice shows. (Not yet verified on real iCloud.)
