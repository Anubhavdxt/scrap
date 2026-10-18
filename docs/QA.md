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
- [ ] The menu bar icon takes the colour of the current pad and changes as you switch pads; Settings > General > "Tint the menu bar icon" turns that off (plain template icon in light and dark menu bars)
- [ ] Esc closes the editor (and closes settings first when it's open); Settings > General > "Escape closes the window" turns that off
- [ ] Code blocks: the ``` lines are not visible (only a thin strip of padding where they were) and the language sits at the panel's top-right; the opening fence comes back when the caret is on it, so the language can be edited; Settings > Markdown marks Dim/Show and raw mode keep the fences visible; a block with no language has no label; a ``` line inside a longer ```` block is shown as code
- [ ] Footer: stats, "Saved just now" becoming "1 min ago"; the `*` button opens the symbol picker, the eye button switches raw/rendered (tooltips "Show raw markdown" and "Show rendered text"), the share button shares the pad text; formatting is in the Format menu and its shortcuts (disabled when empty); the saved text drops away in a narrow window
- [ ] Click the icon: the popover drops down from it and you can type immediately
- [ ] ⌃⌥Space shows and hides it from any app
- [ ] Clicking outside closes it; switching apps closes it; text typed just before closing is saved
- [ ] Right-click the icon: Settings… and Quit work
- [ ] Opens at the size set in Settings > Window (columns × rows) and resizes live when it changes

## Detached window, Dock icon
- [ ] The pin turns the popover into a window of the same size; the pin shows filled and attaches it back; position and size are remembered across hides and relaunches
- [ ] The top bar's ×, ⌘W and (with the setting) Esc hide the window without losing text; the hotkey, the menu bar icon and the Dock icon bring it back
- [ ] The window has no macOS red/yellow/green buttons and no extra title strip, only the top bar with its × (like Tot); dragging the empty part of the top bar moves it; edges resize it, with a sensible minimum; it has rounded corners and a shadow
- [ ] Settings > General: "Show in" Menu bar / Dock / Both. Dock-only: no menu bar icon, the window opens at launch, no pin, "Open as a window" is on and greyed out. Both: Dock icon and menu bar icon; the menu bar icon opens the popover or window per the pin. Menu bar: no Dock icon
- [ ] With a Dock icon the real menu bar shows scrap's menus (Edit, Format, View) and ⌘Q quits; clicking the Dock icon shows the editor
- [ ] "Keep the window above other windows" floats it; switching between popover and window while open keeps the text and caret
- [ ] Settings > General > "The hotkey opens the window at the pointer" (window mode): the hotkey puts the window's top bar under the mouse, on the screen the mouse is on, kept clear of the menu bar and Dock; with it off the window comes back where it was; it has no effect on the popover
- [ ] The gear opens settings attached to the window, and clicking in the editor closes only settings

## Editor
- [ ] ⌘C, ⌘X, ⌘V, ⌘A, ⌘Z and ⇧⌘Z work
- [ ] Markdown is highlighted (headings, bold, italic, code, links, quotes, lists, fenced code) in a few themes, dark and light
- [ ] Lists: Return continues, an empty item ends the list, Return mid-list renumbers, Tab/⇧Tab indent, ⌘Return toggles a checkbox, ⌘Z undoes each in one step
- [ ] Format menu and shortcuts: ⌘B, ⌘I, ⇧⌘X, ⌘E wrap the selection or the word at the cursor and toggle off again; ⌃- inserts a divider; ⌃8 makes or unmakes a task; ⌘Return checks it; each is one undo step
- [ ] The eye button, ⌥⌘R and View > Show Raw Markdown switch to raw (monospaced, the same colours, bold, italics, code chips and panels, but every mark such as `#`, `**`, backticks and `- [ ]` stays visible and no icons are drawn) and back; the choice is remembered; typing in raw mode works
- [ ] Font: prose is the proportional system font by default and code, code blocks and raw text stay monospaced; Settings > Appearance > Font offers System (proportional), System Mono and installed monospaced families; the window size in columns × rows still feels right with each
- [ ] Selecting text highlights it in the pad's colour; the footer dot turns into a pale ring and the counts say "selected"; a thin line separates the counts from the time ("Just now", "5 min ago")
- [ ] Live rendering: headings are larger, **bold**/*italic*/~~strike~~ look bold/italic/struck, `code` has a chip, fenced blocks have a panel, quotes a bar; the syntax marks disappear away from the caret and return on the caret's line; Settings > Appearance: Markdown marks (hide/dim/show) and Colour highlights behave; the file text is never altered
- [ ] Smart bullets: type `○ item` (or pick one from the `*` button); clicking the bullet flips it to ● and strikes the item; the pointer becomes a hand over it; Return continues with an open bullet, an empty bullet ends the list, Backspace right after the bullet removes it, Tab indents, ⌘Return flips it; emoji pairs (❌/✅, ⭕/🔴) work; raw mode shows plain characters
- [ ] Custom smart bullets (Settings > Appearance, at the bottom): "Add a bullet" adds a ready-made pair; edit either side (typing replaces the character); letters, digits and plain keyboard characters are refused with a message; a character already used (built in or yours) is refused; at most eight; removing a pair makes its characters plain text again; a bullet you add shows up at the end of the Smart Bullets group in the `*` picker and works like the built-in ones (click, Return, Backspace, Tab, ⌘Return); the set survives a relaunch
- [ ] The `*` picker: opens as a popover below the `*` button, hanging off the bottom of the editor (popover or window) so it never covers the note, with Smart Bullets, Dividers, Bullets, Checkmarks, Arrows, Numbers, Technical and Symbols; a smart bullet replaces the line's bullet or goes in front of the text; dividers get their own line; symbols go in at the cursor; Esc, a click outside, a second click on `*` or choosing something closes it, and the editor has the keyboard back; with little room below (a window at the bottom of the screen) macOS flips it above
- [ ] Task lists: `- [ ]` shows a ring and `- [x]` a filled check with dimmed struck-through text; clicking the icon toggles it without moving the caret; bullets show as dots; wrapped lines hang under the text; backspace right after a marker removes it
- [ ] Links: pasted URLs, `www.` addresses and `[text](url)` are underlined in the accent colour; the pointer turns into a hand over a task icon (and over a link while holding ⌘); ⌘-click opens the link
- [ ] Return keeps indentation on plain indented lines; Settings > General can turn list continuation and indentation off
- [ ] ⌘+ ⌘− ⌘0 change the font size; View > Wrap Lines toggles wrapping; the font family picker changes the font
- [ ] Very large text (a few hundred KB) stays responsive

## Pads
- [ ] Pad dots: the open pad is a solid disc with a soft halo; a pad with text is a ring with a bold dot in the middle; an empty pad is a thin faint ring; hovering a dot grows it a little; the row doesn't shift when switching pads; the footer carries a tint of the open pad's colour in dark and light themes, and Settings > General > "Tint the footer" turns it off
- [ ] The dots at the top: current is filled, pads with content show a centre dot, hovering shows a preview; clicking switches
- [ ] ⌘1–⌘9 jump to pads; ⌘K or ⌘F opens search with the field already focused (type, ↑↓, Return opens the pad and selects the match, Esc closes); a typo ("recipie") still finds "recipe" under "Closest matches"
- [ ] ⇧⌘⌫ clears the pad after a confirmation (and Esc cancels it)
- [ ] Changing the pad count in Settings hides and restores pads without losing text

## Links
- [ ] With scrap running, `open "scrap://add?text=hello%20world&pad=2"` puts the text in pad 2 and the footer says "Added to pad 2 from a link"; without `pad` it goes where `scrap add` would; text you were typing in the open pad is kept and the addition follows it
- [ ] `open "scrap://open?pad=3"` brings scrap up on pad 3; `scrap://read?...`, a bad pad, an empty or oversized text are ignored with an "Ignored a scrap:// link" notice and change nothing
- [ ] Settings > General > "Let scrap:// links add text to my pads" off: an add is refused with a notice (opening still works)
- [ ] The bookmarklet in the README sends the current page to scrap (the browser asks before opening the link)

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

- [ ] Settings > Appearance > App icon: picking one changes the Dock icon at once; Cobalt restores the original
- [ ] Settings > Window > "Show the pad number in its dot": digits readable in every dot, current dot included (two digits for pad 10+)
