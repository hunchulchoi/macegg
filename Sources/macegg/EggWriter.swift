import Foundation
import Compression

// EGG format constants (ESTsoft EGG specification)
enum EggMagic {
    static let eggHeader: UInt32      = 0x4147_4745  // "EGGA"
    static let fileHeader: UInt32     = 0x0A85_90E3
    static let blockHeader: UInt32    = 0x02B5_0C13
    static let filename: UInt32       = 0x0A85_91AC
    static let windowsFileInfo: UInt32 = 0x2C86_950B
    static let end: UInt32            = 0x08E2_8222
}

enum CompressMethod: UInt8 {
    case store = 0
    case deflate = 1
}

struct Entry {
    let url: URL          // source on disk
    let archivePath: String // relative path inside archive, '/'-separated
    let isDirectory: Bool
    let mtime: Date
}

/// Little-endian byte buffer helpers
extension Data {
    mutating func le<T: FixedWidthInteger>(_ v: T) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            for b in p { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }
}

/// Raw DEFLATE (no zlib header) via Apple Compression framework.
func rawDeflate(_ input: Data) -> Data? {
    if input.isEmpty { return Data() }
    let capacity = input.count + input.count / 10 + 1024
    var out = Data(count: capacity)
    let n = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
        input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            compression_encode_buffer(
                dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                nil, COMPRESSION_ZLIB)
        }
    }
    guard n > 0 else { return nil }
    out.count = n
    return out
}

final class EggWriter {
    static let blockSize = 4 * 1024 * 1024
    private let handle: FileHandle
    private var nextFileID: UInt32 = 0
    var verbose = false

    init(path: String) throws {
        guard FileManager.default.createFile(atPath: path, contents: nil) else {
            throw EggError.cannotCreate(path)
        }
        handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        var h = Data()
        h.le(EggMagic.eggHeader)
        h.le(UInt16(0x0100))                        // version 1.0
        h.le(UInt32.random(in: 1...UInt32.max))     // header id
        h.le(UInt32(0))                             // reserved
        h.le(EggMagic.end)                          // end of egg header (no extra fields)
        try handle.write(contentsOf: h)
    }

    func add(_ e: Entry) throws {
        let fileID = nextFileID
        nextFileID += 1

        let size: UInt64 = e.isDirectory ? 0 :
            UInt64((try FileManager.default.attributesOfItem(atPath: e.url.path)[.size] as? NSNumber)?.uint64Value ?? 0)

        var h = Data()
        h.le(EggMagic.fileHeader)
        h.le(fileID)
        h.le(size)

        // Filename extra field: UTF-8, NFC, '\' separators, directories end with '\'
        var name = e.archivePath.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "/", with: "\\")
        if e.isDirectory && !name.hasSuffix("\\") { name += "\\" }
        let nameBytes = Data(name.utf8)
        h.le(EggMagic.filename)
        if nameBytes.count > 0xFFFF {
            h.le(UInt8(0x01)); h.le(UInt32(nameBytes.count))
        } else {
            h.le(UInt8(0x00)); h.le(UInt16(nameBytes.count))
        }
        h.append(nameBytes)

        // Windows file info: FILETIME + attribute
        h.le(EggMagic.windowsFileInfo)
        h.le(UInt8(0))
        h.le(UInt16(9))
        let ft = UInt64(max(0, (e.mtime.timeIntervalSince1970 + 11_644_473_600) * 10_000_000))
        h.le(ft)
        h.le(UInt8(e.isDirectory ? 0x10 : 0x20))

        h.le(EggMagic.end)
        try handle.write(contentsOf: h)

        if verbose { print("  adding: \(name)") }
        guard !e.isDirectory else { return }

        let input = try FileHandle(forReadingFrom: e.url)
        defer { try? input.close() }
        var written: UInt64 = 0
        repeat {
            let chunk = try input.read(upToCount: Self.blockSize) ?? Data()
            if chunk.isEmpty && written > 0 { break }
            try writeBlock(chunk)
            written += UInt64(chunk.count)
            if chunk.isEmpty { break }
        } while written < size
    }

    private func writeBlock(_ raw: Data) throws {
        var method = CompressMethod.store
        var payload = raw
        if !raw.isEmpty, let d = rawDeflate(raw), d.count < raw.count {
            method = .deflate
            payload = d
        }
        var b = Data()
        b.le(EggMagic.blockHeader)
        b.le(method.rawValue)
        b.le(UInt8(0))                    // compress hint
        b.le(UInt32(raw.count))
        b.le(UInt32(payload.count))
        b.le(CRC32.checksum(raw))
        b.le(EggMagic.end)
        try handle.write(contentsOf: b)
        try handle.write(contentsOf: payload)
    }

    func finish() throws {
        var t = Data()
        t.le(EggMagic.end)                // end of archive
        try handle.write(contentsOf: t)
        try handle.close()
    }
}

enum EggError: Error, CustomStringConvertible {
    case cannotCreate(String)
    case notFound(String)
    var description: String {
        switch self {
        case .cannotCreate(let p): return "cannot create \(p)"
        case .notFound(let p): return "not found: \(p)"
        }
    }
}
