# Contributing

1. Fork or branch from `main`: `feat/…`, `fix/…`, `chore/…`.
2. Keep PRs small and focused. Title them with Conventional Commits (`feat: add palette`).
3. `swift build && swift test` must pass. For UI changes, also run the relevant parts of [docs/QA.md](docs/QA.md).
4. Sign your commits (SSH or GPG). `main` requires verified signatures.
5. PRs are squash-merged.
6. Don't use SwiftUI's `@State`: on the macOS 27 SDK it is a macro that only Xcode can expand, and the app must build with just the Command Line Tools. Use `@Local` (same behaviour; `Sources/ScrapApp/LocalState.swift`). `scripts/check-clt.sh` and a test enforce this.

## Releasing (maintainer)

1. Bump the version in `Resources/Info.plist` and `Sources/ScrapCore/ScrapCore.swift` in a PR, and merge it.
2. Tag and publish: `git tag -s vX.Y.Z -m "scrap X.Y.Z" && git push origin vX.Y.Z`, then `gh release create vX.Y.Z --notes-file …`.
3. Publishing the release runs `.github/workflows/release.yml`: it builds the universal app on a runner (`make dist`), attests it and attaches `scrap-X.Y.Z-macos.tar.gz` and its `.sha256`.
4. Point `Formula/scrap.rb` at that asset (its url and the sha256 from the release) in a PR. Homebrew installs the prebuilt build; `--HEAD` builds from source with just the Command Line Tools.
