class Scrap < Formula
  desc "Free, open-source, keyboard-first scratchpad for the macOS menu bar"
  homepage "https://github.com/Anubhavdxt/scrap"
  url "https://github.com/Anubhavdxt/scrap/releases/download/v0.4.1/scrap-0.4.1-macos.tar.gz"
  sha256 "3e454b7d19a21263936bdd2e283a1a91cb808948f61003388665eb9443230999"
  license "MIT"
  head "https://github.com/Anubhavdxt/scrap.git", branch: "main"

  depends_on macos: :sonoma

  def install
    if build.head?
      # Builds with just the Command Line Tools (the app doesn't use SwiftUI's @State macro, which needs Xcode).
      system "make", "app", "SWIFTFLAGS=--disable-sandbox"
      bin.install ".build/release/scrap-cli" => "scrap"
      prefix.install "build/Scrap.app"
    else
      # The release build GitHub Actions made from the tag: universal, ad-hoc signed, nothing compiled here.
      bin.install "bin/scrap"
      prefix.install "Scrap.app"
    end
  end

  def caveats
    <<~EOS
      To use the menu bar app, link it into Applications and open it:
        scrap link
        open -a Scrap

      To uninstall, run `scrap uninstall`: it removes that link and then runs
      `brew uninstall scrap`. (Your pads are never touched.)

      Pads live in iCloud Drive/scrap (or ~/Documents/scrap). Change that in
      ~/.config/scrap/config.json:  { "folder": "~/notes", "pads": 7 }
    EOS
  end

  test do
    assert_match "scrap", shell_output("#{bin}/scrap --version")
    (testpath/".config/scrap").mkpath
    (testpath/".config/scrap/config.json").write %Q({ "folder": "#{testpath}/pads" })
    assert_equal "pad 7\n", shell_output("#{bin}/scrap add hello")
    assert_equal "hello\n", shell_output("#{bin}/scrap show 7")
  end
end
