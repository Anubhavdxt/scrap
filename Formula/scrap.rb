class Scrap < Formula
  desc "Free, open-source, keyboard-first scratchpad for the macOS menu bar"
  homepage "https://github.com/Anubhavdxt/scrap"
  url "https://github.com/Anubhavdxt/scrap/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "a9a226cf090b7f1814b55b27e773d2289625b2bcf4c6351a29f639a341274df9"
  license "MIT"
  head "https://github.com/Anubhavdxt/scrap.git", branch: "main"

  depends_on macos: :sonoma

  def install
    # Built from source on the user's Mac: no download quarantine, so no Gatekeeper warning.
    system "make", "app", "SWIFTFLAGS=--disable-sandbox"
    bin.install ".build/release/scrap-cli" => "scrap"
    prefix.install "build/Scrap.app"
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
