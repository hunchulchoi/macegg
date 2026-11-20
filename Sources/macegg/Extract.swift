import Foundation

let extractUsage = """
usage: macegg -x [-C dir] [-p password] <archive.egg|archive.alz>...
  -C DIR    parent directory to extract into (default: next to the archive)
  -p PASS   password for encrypted archives
Extraction is delegated to `unegg`. Each archive goes into a folder named after it;
if the archive holds a single top-level item, that item is placed directly instead.
Existing files are never overwritten; a numbered name is used instead.
"""

func findUnegg() -> String? {
    let env = ProcessInfo.processInfo.environment
    var dirs = (env["PATH"] ?? "").split(separator: ":").map(String.init)
    dirs += ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/go/bin"]
    for d in dirs {
        let p = (d as NSString).appendingPathComponent("unegg")
        if FileManager.default.isExecutableFile(atPath: p) { return p }
    }
    return nil
}

/// "name", "name 2", "name 3"... (keeps extension for files)
func uniqueItemPath(_ path: String) -> String {
    let fm = FileManager.default
    guard fm.fileExists(atPath: path) else { return path }
    let url = URL(fileURLWithPath: path)
    let dir = url.deletingLastPathComponent()
    let ext = url.pathExtension
    let stem = url.deletingPathExtension().lastPathComponent
    var i = 2
    while true {
        let name = ext.isEmpty ? "\(stem) \(i)" : "\(stem) \(i).\(ext)"
        let p = dir.appendingPathComponent(name).path
        if !fm.fileExists(atPath: p) { return p }
        i += 1
    }
}

func runExtract(_ argv: [String]) -> Never {
    var args = argv
    var parent: String?
    var password: String?
    var archives: [String] = []
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "-C": guard !args.isEmpty else { print(extractUsage); exit(2) }; parent = args.removeFirst()
        case "-p": guard !args.isEmpty else { print(extractUsage); exit(2) }; password = args.removeFirst()
        case "-h", "--help": print(extractUsage); exit(0)
        default: archives.append(a)
        }
    }
    guard !archives.isEmpty else { print(extractUsage); exit(2) }
    guard let unegg = findUnegg() else {
        FileHandle.standardError.write(Data("macegg: unegg not found (install unegg first)\n".utf8))
        exit(1)
    }

    let fm = FileManager.default
    var failed = false
    for a in archives {
        let archive = URL(fileURLWithPath: a).standardizedFileURL
        guard fm.fileExists(atPath: archive.path) else {
            FileHandle.standardError.write(Data("macegg: not found: \(archive.path)\n".utf8))
            failed = true; continue
        }
        let parentDir = parent.map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? archive.deletingLastPathComponent()
        let dest = uniqueItemPath(parentDir.appendingPathComponent(
            archive.deletingPathExtension().lastPathComponent).path)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: unegg)
        p.arguments = ["-q"] + (password.map { ["-p", $0] } ?? []) + ["-C", dest, archive.path]
        p.standardInput = FileHandle.nullDevice
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = errPipe
        do { try p.run() } catch {
            FileHandle.standardError.write(Data("macegg: cannot run unegg: \(error)\n".utf8))
            exit(1)
        }
        let out = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        if p.terminationStatus != 0 {
            FileHandle.standardError.write(out)
            FileHandle.standardError.write(Data("macegg: failed to extract \(archive.lastPathComponent)\n".utf8))
            if let items = try? fm.contentsOfDirectory(atPath: dest), items.isEmpty {
                try? fm.removeItem(atPath: dest)
            }
            failed = true; continue
        }

        // Single top-level item: lift it out of the wrapper folder.
        var result = dest
        if let items = try? fm.contentsOfDirectory(atPath: dest).filter({ $0 != ".DS_Store" }), items.count == 1 {
            let tmp = uniqueItemPath(dest + ".macegg-tmp")
            let target = parentDir.appendingPathComponent(items[0]).path
            do {
                try fm.moveItem(atPath: dest, toPath: tmp)
                let finalPath = target == dest ? dest : uniqueItemPath(target)
                try fm.moveItem(atPath: tmp + "/" + items[0], toPath: finalPath)
                try fm.removeItem(atPath: tmp)
                result = finalPath
            } catch {
                if fm.fileExists(atPath: tmp) && !fm.fileExists(atPath: dest) { try? fm.moveItem(atPath: tmp, toPath: dest) }
            }
        }
        print(result)
    }
    exit(failed ? 1 : 0)
}
