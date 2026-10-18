<p align="center"><img src="docs/logo.png" width="128" alt="scrap logo"></p>

# scrap

A free, open-source scratchpad that lives in your Mac's menu bar. A fixed set of pads (7 by default), plain Markdown files, keyboard-first, themeable. Inspired by Tot, with no paid tier.

- **Pads:** numbered colour dots at the top, `⌘1`–`⌘9` to jump, `⌘K` to search, `⇧⌘⌫` to clear
- **Plain files:** pads are `1.md` … `N.md` in a folder you control, iCloud Drive by default
- **Markdown:** headings, emphasis, links and fenced code are highlighted, with per-language colours for Swift, JS/TS, Python, shell, JSON, SQL, Go, Rust, C/C++, Java/Kotlin, Ruby, HTML/XML, CSS, YAML, TOML/INI, diff and Dockerfile/Makefile (other languages get a generic lexer)
- **Themes:** 9 editor themes, each in dark and light
- **CLI:** `scrap add "buy milk"`, `pbpaste | scrap add -p 2`, `scrap show 2`, `scrap list`, `scrap link`
- **Sync-safe:** if sync leaves a conflicting copy of a pad, both versions are kept

Requires macOS 14 or later.

## Install

### Homebrew (builds from source)

    brew tap Anubhavdxt/scrap https://github.com/Anubhavdxt/scrap
    brew install scrap
    scrap link
    open -a Scrap

`scrap link` links the app into `/Applications`. It only ever replaces its own link, never a real `Scrap.app`. Run `scrap unlink` before `brew uninstall scrap` to remove it.

Needs the Xcode Command Line Tools (`xcode-select --install`). Because it is built on your Mac, there is no Gatekeeper warning.

### From source

    git clone https://github.com/Anubhavdxt/scrap.git
    cd scrap && make install

`make install` puts `Scrap.app` in `/Applications` and the CLI at `/usr/local/bin/scrap`. `make uninstall` removes both.

## Use

| | |
|---|---|
| Show or hide | `⌃⌥Space` (changeable in Settings), or click the menu bar icon |
| Quick switch | `⌘K` |
| Go to pad 1–9 | `⌘1` – `⌘9` |
| Clear pad | `⇧⌘⌫` |
| Format | `⌘B` bold, `⌘I` italic, `⇧⌘X` strikethrough, `⌘E` code, `⌃-` divider (all toggle; they wrap the selection or the word at the cursor) |
| Rendered or raw | The eye button in the footer (or `⌥⌘R`, View menu) switches between the rendered view and the raw file: the same colours and styling, monospaced, with every Markdown mark (`#`, `**`, backticks, `- [ ]`) left visible instead of hidden or drawn as an icon. Rendered text uses the proportional system font by default (Settings > Appearance > Font); code stays monospaced |
| Styling | Markdown is styled as you type: real bold, italic and ~~strikethrough~~, sized headings, `code` chips, code-block panels and quote bars. The `**`, `#`, backticks and `[ ]` marks hide except on the line you're editing (Settings: hide, dim or show), and Colour highlights can be turned off |
| Smart bullets | Tot-style bullets that are real characters in the text: ○ ● □ ■ ▷ ▶ ☆ ★ – ➕ − ✓ ❌ ✅ ⭕ 🔴. Click one to flip it between open and done (done items dim and strike through). Return continues the list, an empty one ends it, Backspace removes the bullet, and ⌘Return flips it too. Text pasted from Tot works as is |
| Symbols | The `*` button in the footer opens a picker: smart bullets, dividers, bullets, checkmarks, arrows, numbers, key symbols and more |
| Tasks | `- [ ]` items are drawn as clickable circles: click to check, and done tasks dim and strike through. Bullets are drawn as dots. The file stays plain Markdown |
| Links | URLs you paste or type, and `[text](url)` links, are underlined in the accent colour; `⌘`-click opens them |
| Lists and tasks | `Return` continues a list (an empty item ends it) and keeps indentation, `Tab` / `⇧Tab` indent, `⌃8` makes or unmakes a task, `⌘Return` checks or unchecks it |
| Font size | `⌘+` / `⌘−`, `⌘0` resets (also in Settings, with font family and line wrapping) |
| Window | The pin in the top bar turns the popover into a normal resizable window (and back); Settings can show scrap in the menu bar, the Dock, or both, and keep the window above other windows |
| Pad dots | A solid disc with a halo is the open pad, a ring with a dot in the middle has text, a thin faint ring is empty. The footer takes a tint of the open pad's colour (Settings can turn that off) |
| Pointer | With *The hotkey opens the window at the pointer* (Settings > General), the hotkey brings the window up under your mouse, on whichever screen it is, instead of where it was |
| Footer | the pad's line, word and character counts, when it was last saved, and buttons for tasks, formatting and sharing |
| Settings | the gear, `⌘,`, or right-click the menu bar icon |

Settings has the shortcut recorder, pad count and folder, launch at login, theme, and the opening window size in columns × rows, like a terminal.

## Configuration

Optional `~/.config/scrap/config.json`, shared by the app and the CLI:

    { "folder": "~/notes", "pads": 7 }

`scrap add` puts text in the last empty pad, or appends to the last pad if none is empty. Use `-p N` to pick one.

## Development

    swift build
    swift test
    make app && open build/Scrap.app
    make icons   # regenerate the logo assets from scripts/make_icon.swift

Work happens on feature branches and is squash-merged by pull request. See [CONTRIBUTING.md](CONTRIBUTING.md) and [TODO.md](TODO.md).

## License

MIT
