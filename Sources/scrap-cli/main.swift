import Darwin
import Foundation
import ScrapCore

let usage = """
usage: scrap <command>

  add [-p <n>] [text…]   put text in a pad, from the arguments or stdin
  show <n>               print pad n
  list                   list the pads with their first lines
  path                   print the pad folder
  link [--dir <folder>]  link Scrap.app into /Applications (after a Homebrew install)
  unlink                 remove that link (run before `brew uninstall scrap`)
  --version, --help

Without -p, add fills the last empty pad, or appends to the last pad if none is empty.

examples:
  scrap add "buy milk"
  pbpaste | scrap add -p 2

Settings live in ~/.config/scrap/config.json:
  { "folder": "~/notes", "pads": 7 }
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("scrap: \(message)\n".utf8))
    exit(1)
}

func openStore() -> PadStore {
    do { return try PadStore(folder: Config.folder(), count: Config.padCount()) } catch { fail("can't open pad folder: \(error.localizedDescription)") }
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(2)
}
args.removeFirst()

switch command {
case "add":
    var pad: Int?
    var words: [String] = []
    var i = 0
    while i < args.count {
        if args[i] == "-p" || args[i] == "--pad" {
            guard i + 1 < args.count, let n = Int(args[i + 1]) else { fail("\(args[i]) needs a pad number") }
            pad = n
            i += 2
        } else {
            words.append(args[i])
            i += 1
        }
    }
    var text = words.joined(separator: " ")
    if words.isEmpty || words == ["-"] {
        if isatty(STDIN_FILENO) != 0 && words.isEmpty { fail("nothing to add. Pass text or pipe it in.") }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let input = String(data: data, encoding: .utf8) else { fail("stdin isn't valid UTF-8") }
        text = input
    }
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fail("nothing to add") }
    do {
        let added = try openStore().add(text, to: pad)
        print("pad \(added.number)")
    } catch { fail(error.localizedDescription) }
case "show":
    guard let arg = args.first, let n = Int(arg) else { fail("usage: scrap show <n>") }
    let store = openStore()
    guard let pad = store.pad(n) else { fail(PadStoreError.noSuchPad(n, max: store.count).localizedDescription) }
    do { print(try store.read(pad), terminator: "") } catch { fail(error.localizedDescription) }
case "list":
    for pad in openStore().list() { print("\(pad.number)\t\(pad.isEmpty ? "(empty)" : pad.preview)") }
case "link", "unlink":
    var folder = "/Applications"
    if let i = args.firstIndex(of: "--dir") {
        guard i + 1 < args.count else { fail("--dir needs a folder") }
        folder = args[i + 1]
    }
    let applications = URL(fileURLWithPath: folder)
    do {
        if command == "unlink" {
            print(try AppLinker.unlink(from: applications) ? "removed \(applications.path)/Scrap.app link" : "nothing to remove")
        } else {
            let exe = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
            guard let app = AppLinker.locateApp(executable: exe) else { throw AppLinker.LinkError.appNotFound }
            switch try AppLinker.link(app: app, into: applications) {
            case .linked(let dest), .relinked(let dest): print("linked \(dest.path) -> \(app.path)\nopen it with: open -a Scrap")
            case .alreadyLinked(let dest): print("already linked: \(dest.path)")
            }
        }
    } catch { fail(error.localizedDescription) }
case "path":
    print(Config.folder().path)
case "--version", "-v", "version":
    print("scrap \(Scrap.version)")
case "--help", "-h", "help":
    print(usage)
default:
    FileHandle.standardError.write(Data("scrap: unknown command '\(command)'\n\n\(usage)\n".utf8))
    exit(2)
}
