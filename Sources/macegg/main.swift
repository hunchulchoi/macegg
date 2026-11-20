import Foundation

let usage = """
usage: macegg [-v] [-o output.egg] <file|folder>...     compress
       macegg -x [-C dir] [-p password] <archive.egg>...  extract (via unegg)
  -o PATH   output archive (default: <first item>.egg, or Archive.egg for multiple items)
  -v        verbose
Existing output is never overwritten; a numbered name is used instead.
"""

if CommandLine.arguments.dropFirst().first == "-x" {
    runExtract(Array(CommandLine.arguments.dropFirst(2)))
}

let skipNames: Set<String> = [".DS_Store", "__MACOSX", ".localized"]

func collect(_ root: URL, base: String) throws -> [Entry] {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: root.path, isDirectory: &isDir) else { throw EggError.notFound(root.path) }
    let rv = try root.resourceValues(forKeys: [.contentModificationDateKey])
    var out = [Entry(url: root, archivePath: base, isDirectory: isDir.boolValue,
                     mtime: rv.contentModificationDate ?? Date())]
    guard isDir.boolValue else { return out }
    let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])
        .filter { !skipNames.contains($0.lastPathComponent) && !$0.lastPathComponent.hasPrefix("._") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    for c in children {
        if (try? c.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
        out += try collect(c, base: base + "/" + c.lastPathComponent)
    }
    return out
}

func uniquePath(_ path: String) -> String {
    let fm = FileManager.default
    guard fm.fileExists(atPath: path) else { return path }
    let url = URL(fileURLWithPath: path)
    let dir = url.deletingLastPathComponent()
    let stem = url.deletingPathExtension().lastPathComponent
    var i = 2
    while true {
        let p = dir.appendingPathComponent("\(stem) \(i).egg").path
        if !fm.fileExists(atPath: p) { return p }
        i += 1
    }
}

var args = Array(CommandLine.arguments.dropFirst())
var output: String?
var verbose = false
var inputs: [String] = []
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "-o": guard !args.isEmpty else { print(usage); exit(2) }; output = args.removeFirst()
    case "-v": verbose = true
    case "-h", "--help": print(usage); exit(0)
    default: inputs.append(a)
    }
}
guard !inputs.isEmpty else { print(usage); exit(2) }

let urls = inputs.map { URL(fileURLWithPath: $0).standardizedFileURL }
var outPath: String
if let o = output {
    outPath = URL(fileURLWithPath: o).standardizedFileURL.path
    if !outPath.lowercased().hasSuffix(".egg") { outPath += ".egg" }
} else {
    let dir = urls[0].deletingLastPathComponent()
    let name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Archive"
    outPath = dir.appendingPathComponent(name + ".egg").path
}
outPath = uniquePath(outPath)

do {
    var entries: [Entry] = []
    for u in urls { entries += try collect(u, base: u.lastPathComponent) }
    entries.removeAll { $0.url.path == outPath }
    let w = try EggWriter(path: outPath)
    w.verbose = verbose
    do {
        for e in entries { try w.add(e) }
        try w.finish()
    } catch {
        try? FileManager.default.removeItem(atPath: outPath)
        throw error
    }
    print(outPath)
} catch {
    FileHandle.standardError.write(Data("macegg: \(error)\n".utf8))
    exit(1)
}
