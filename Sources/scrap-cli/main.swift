import Darwin
import Foundation
import ScrapCore

let usage = """
usage: scrap <command>

  add [-n <name>] [text…]   create a pad from the arguments, or from stdin
  list                      list pads, newest first
  path                      print the pad folder
  --version, --help

examples:
  scrap add "buy milk"
  pbpaste | scrap add -n clipboard
  echo "# idea" | scrap add

The folder defaults to iCloud Drive/scrap. Override it in ~/.config/scrap/config.json:
  { "folder": "~/notes" }
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("scrap: \(message)\n".utf8))
    exit(1)
}

func openStore() -> PadStore {
    do { return try PadStore(folder: Config.folder()) } catch { fail("can't open pad folder: \(error.localizedDescription)") }
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(2)
}
args.removeFirst()

switch command {
case "add":
    var name: String?
    var words: [String] = []
    var i = 0
    while i < args.count {
        if args[i] == "-n" || args[i] == "--name" {
            guard i + 1 < args.count else { fail("\(args[i]) needs a value") }
            name = args[i + 1]
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
        let pad = try openStore().add(text, name: name)
        print(pad.url.path)
    } catch { fail(error.localizedDescription) }
case "list":
    do { for pad in try openStore().list() { print(pad.name) } } catch { fail(error.localizedDescription) }
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
