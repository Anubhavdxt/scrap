<p align="center"><img src="docs/logo.png" width="128" alt="scrap logo"></p>

# scrap

A free, open-source scratchpad that lives in your Mac's menu bar. A fixed set of pads (7 by default), plain Markdown files, keyboard-first, themeable. Inspired by Tot, with no paid tier.

- **Pads:** numbered colour dots at the top; switch with `⌘1`–`⌘9` or search with `⌘K`. Pads are `1.md` … `N.md` in a folder you choose, iCloud Drive by default
- **Live Markdown:** styled as you type, and the `#`, `**` and backticks hide away from the line you're editing. 9 themes in dark and light, and per-language colours in code blocks
- **Raw view:** `⌥⌘R` shows the same colours with every mark visible
- **Bullets and tasks:** `- [ ]` tasks and smart bullets (○ ● □ ■ ▷ ▶ ☆ ★ and more, plus your own) flip between open and done when you click them
- **Menu bar, Dock or both:** a popover, or a resizable window you can pin above other windows
- **CLI:** `scrap add "buy milk"`, `pbpaste | scrap add -p 2`, `scrap show 2`, `scrap list`
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
| Show or hide | `⌃⌥Space` (changeable in Settings) |
| Search all pads · pad 1–9 | `⌘K` or `⌘F` · `⌘1` – `⌘9` |
| Clear pad | `⇧⌘⌫` |
| Bold · italic · strikethrough · code | `⌘B` · `⌘I` · `⇧⌘X` · `⌘E` |
| Divider · make task · check | `⌃-` · `⌃8` · `⌘↩` |
| Raw or rendered | `⌥⌘R` |
| Font size | `⌘+` · `⌘−` · `⌘0` |
| Settings | `⌘,` |

A few things worth knowing:

- Return continues a list (an empty item ends it) and keeps indentation; Tab and Shift-Tab indent.
- Click a smart bullet or a task circle to flip it; ⌘Return does it from the keyboard. The `*` button in the footer opens a picker of bullets, dividers, arrows and symbols below the window.
- URLs and `[text](url)` links are underlined; ⌘-click opens them.
- The pin in the top bar turns the popover into a window. The footer tints with the open pad's colour, and shows counts for what you've selected.
- Settings covers the shortcut, pad count and folder, theme, fonts, window size (in columns × rows), what shows in the menu bar and Dock, and launch at login.

## Configuration

Optional `~/.config/scrap/config.json`, shared by the app and the CLI:

    { "folder": "~/notes", "pads": 7 }

`scrap add` puts text in the last empty pad, or appends to the last pad if none is empty. Use `-p N` to pick one.

## Links

`scrap://` links open a pad or add text, so other tools can talk to scrap:

    scrap://open?pad=3
    scrap://add?text=buy%20milk&pad=3      (pad is optional: it goes where `scrap add` would put it)

- Percent-encode the text (a space is `%20`, a newline `%0A`); a `+` is a plain plus. The limit is 20 KB.
- A link can never read a pad back, and an addition is announced in the footer. Turn it off in Settings > General.
- A browser bookmarklet that sends the page to scrap:

      javascript:location.href='scrap://add?text='+encodeURIComponent(document.title+'\n'+location.href)

- In Shortcuts, use *Open URL* with a `scrap://` link, or *Run Shell Script* with `scrap add "…"`.

## Development

    swift build
    swift test
    make app && open build/Scrap.app
    make icons   # regenerate the logo assets from scripts/make_icon.swift

Work happens on feature branches and is squash-merged by pull request. See [CONTRIBUTING.md](CONTRIBUTING.md) and [TODO.md](TODO.md).

## License

MIT
