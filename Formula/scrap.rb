class Scrap < Formula
  desc "Free, open-source, keyboard-first scratchpad for the macOS menu bar"
  homepage "https://github.com/Anubhavdxt/scrap"
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
        ln -sf "#{opt_prefix}/Scrap.app" /Applications/Scrap.app
        open -a Scrap

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
