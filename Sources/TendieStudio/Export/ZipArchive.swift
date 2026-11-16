import Foundation
#if canImport(Compression)
import Compression
#endif

/// Minimal dependency-free ZIP reader/writer (methods 0 = stored, 8 = deflate).
/// Written because the .tendies format is a plain ZIP and we want zero dependencies.
struct ZipEntry: Equatable {
    var path: String
    var data: Data
    var isDirectory: Bool { path.hasSuffix("/") }
}

enum ZipError: Error, LocalizedError {
    case malformed(String), unsupported(String)
    var errorDescription: String? {
        switch self { case .malformed(let s): return "Invalid ZIP: \(s)"; case .unsupported(let s): return "Unsupported ZIP feature: \(s)" }
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
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

private extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { for s in stride(from: 0, to: 32, by: 8) { append(UInt8((v >> UInt32(s)) & 0xFF)) } }
    func u16(at o: Int) -> Int { Int(self[startIndex + o]) | Int(self[startIndex + o + 1]) << 8 }
    func u32(at o: Int) -> Int { u16(at: o) | u16(at: o + 2) << 16 }
}

enum ZipArchive {
    // MARK: Writing
    static func write(_ entries: [ZipEntry], date: Date = Date()) -> Data {
        let (dosTime, dosDate) = dosDateTime(date)
        var out = Data(), central = Data()
        for e in entries {
            let name = Data(e.path.utf8)
            let crc = e.isDirectory ? 0 : CRC32.checksum(e.data)
            var method: UInt16 = 0
            var payload = e.data
            if !e.isDirectory, e.data.count > 256, let z = deflate(e.data), z.count < e.data.count {
                method = 8; payload = z
            }
            let offset = out.count
            out.le32(0x0403_4B50); out.le16(20); out.le16(0x0800)      // UTF-8 names
            out.le16(method); out.le16(dosTime); out.le16(dosDate)
            out.le32(crc); out.le32(UInt32(payload.count)); out.le32(UInt32(e.data.count))
            out.le16(UInt16(name.count)); out.le16(0)
            out.append(name); out.append(payload)

            central.le32(0x0201_4B50); central.le16(20); central.le16(20); central.le16(0x0800)
            central.le16(method); central.le16(dosTime); central.le16(dosDate)
            central.le32(crc); central.le32(UInt32(payload.count)); central.le32(UInt32(e.data.count))
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0)
            central.le32(e.isDirectory ? 0x10 : 0)       // external attrs (dir flag)
            central.le32(UInt32(offset)); central.append(name)
        }
        let cdOffset = out.count
        out.append(central)
        out.le32(0x0605_4B50); out.le16(0); out.le16(0)
        out.le16(UInt16(entries.count)); out.le16(UInt16(entries.count))
        out.le32(UInt32(central.count)); out.le32(UInt32(cdOffset)); out.le16(0)
        return out
    }

    private static func dosDateTime(_ d: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: d)
        let y = max(1980, c.year ?? 1980) - 1980
        let t = ((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2)
        let dt = (y << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1)
        return (UInt16(t), UInt16(dt))
    }

    // MARK: Reading
    static func read(_ data: Data) throws -> [ZipEntry] {
        let n = data.count
        guard n >= 22 else { throw ZipError.malformed("too small") }
        var eocd = -1
        var i = n - 22
        while i >= max(0, n - 22 - 65_535) {
            if data.u32(at: i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.malformed("end of central directory not found") }
        let count = data.u16(at: eocd + 10)
        var p = data.u32(at: eocd + 16)
        var result: [ZipEntry] = []
        for _ in 0..<count {
            guard p + 46 <= n, data.u32(at: p) == 0x0201_4B50 else { throw ZipError.malformed("bad central header") }
            let method = data.u16(at: p + 10)
            let csize = data.u32(at: p + 20), usize = data.u32(at: p + 24)
            let nlen = data.u16(at: p + 28), elen = data.u16(at: p + 30), clen = data.u16(at: p + 32)
            let lho = data.u32(at: p + 42)
            guard p + 46 + nlen <= n else { throw ZipError.malformed("name out of range") }
            let nameData = data.subdata(in: (data.startIndex + p + 46)..<(data.startIndex + p + 46 + nlen))
            let path = String(decoding: nameData, as: UTF8.self)
            p += 46 + nlen + elen + clen
            guard lho + 30 <= n, data.u32(at: lho) == 0x0403_4B50 else { throw ZipError.malformed("bad local header for \(path)") }
            let start = lho + 30 + data.u16(at: lho + 26) + data.u16(at: lho + 28)
            guard start + csize <= n else { throw ZipError.malformed("data out of range for \(path)") }
            let raw = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + csize))
            switch method {
            case 0: result.append(ZipEntry(path: path, data: raw))
            case 8:
                guard let inflated = inflate(raw, expected: usize) else { throw ZipError.malformed("cannot inflate \(path)") }
                result.append(ZipEntry(path: path, data: inflated))
            default: throw ZipError.unsupported("compression method \(method) in \(path)")
            }
        }
        return result
    }

    // MARK: Raw DEFLATE via Apple's Compression framework
    // COMPRESSION_ZLIB is raw DEFLATE (no zlib header), exactly what ZIP method 8 stores.
    private static func deflate(_ d: Data) -> Data? {
        #if canImport(Compression)
        let cap = d.count + 1024
        var out = Data(count: cap)
        let written = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            d.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, cap,
                                          src.bindMemory(to: UInt8.self).baseAddress!, d.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return out.prefix(written)
        #else
        return nil
        #endif
    }

    private static func inflate(_ d: Data, expected: Int) -> Data? {
        #if canImport(Compression)
        if expected == 0 { return Data() }
        var out = Data(count: expected)
        let n = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            d.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, expected,
                                          src.bindMemory(to: UInt8.self).baseAddress!, d.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n == expected ? out : nil
        #else
        return nil
        #endif
    }
}
