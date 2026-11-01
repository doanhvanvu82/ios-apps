import Foundation
import ZIPFoundation

/// Đọc chỉ mục archive `.rpa` của Ren'Py (RPA-2.0 / RPA-3.0).
///
/// Dòng đầu: `RPA-3.0 <offset hex> <key hex>`; tại `offset` là chỉ mục nén zlib,
/// dạng pickle `{tên: [(offset ^ key, độ dài ^ key, prefix)]}`. RenPyNative dùng
/// để tách rpa > 2 GB thành tệp riêng: runtime web là wasm32, offset vượt 2 GB
/// làm Ren'Py báo "Python int too large to convert to C long".
enum RenPyArchive {
    struct Entry {
        let offset: Int
        let length: Int
        let prefix: Data
    }

    enum ArchiveError: Error { case notRPA, corrupt, unsupportedPickle(UInt8) }

    static func entries(of url: URL) throws -> [String: Entry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let head = try handle.read(upToCount: 64),
              let line = String(data: head.prefix { $0 != 0x0A }, encoding: .ascii) else { throw ArchiveError.notRPA }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "RPA-3.0" || parts[0] == "RPA-2.0",
              let indexOffset = UInt64(parts[1], radix: 16) else { throw ArchiveError.notRPA }
        let key = parts[0] == "RPA-3.0" && parts.count >= 3 ? Int(parts[2], radix: 16) ?? 0 : 0

        try handle.seek(toOffset: indexOffset)
        guard let compressed = try handle.readToEnd(), compressed.count > 2 else { throw ArchiveError.corrupt }
        let index = try inflateZlib(compressed)

        guard case .dict(let dict) = try Pickle.load(index) else { throw ArchiveError.corrupt }
        var result: [String: Entry] = [:]
        for (name, value) in dict.pairs {
            guard let name = name.string else { continue }
            guard case .list(let list) = value, let first = list.items.first,
                  case .tuple(let fields) = first, fields.count >= 2,
                  let offset = fields[0].int, let length = fields[1].int else { continue }
            let prefix = fields.count > 2 ? fields[2].bytes ?? Data() : Data()
            result[name] = Entry(offset: offset ^ key, length: length ^ key, prefix: prefix)
        }
        return result
    }

    /// zlib = 2 byte header + deflate thô (+ adler32) — ZIPFoundation giải deflate thô.
    private static func inflateZlib(_ data: Data) throws -> Data {
        let body = data.subdata(in: data.startIndex + 2 ..< data.endIndex)
        var out = Data()
        _ = try Data.decompress(size: Int64(body.count), bufferSize: 64 * 1024, skipCRC32: true,
                                provider: { position, size in
                                    let start = body.startIndex + Int(position)
                                    return body.subdata(in: start ..< min(start + size, body.endIndex))
                                },
                                consumer: { out.append($0) })
        return out
    }
}

// MARK: - Pickle tối thiểu

/// Giá trị pickle — list/dict là class vì opcode APPEND/SETITEMS sửa đối tượng
/// đã lưu trong memo.
enum PickleValue {
    case int(Int), string(String), bytes(Data), list(PickleList), tuple([PickleValue]), dict(PickleDict)
    case none, bool(Bool), float(Double)

    var int: Int? { if case .int(let v) = self { return v }; return nil }
    var string: String? {
        switch self {
        case .string(let s): return s
        case .bytes(let d): return String(data: d, encoding: .utf8)
        default: return nil
        }
    }
    var bytes: Data? {
        switch self {
        case .bytes(let d): return d
        case .string(let s): return s.data(using: .isoLatin1)
        default: return nil
        }
    }
}

final class PickleList { var items: [PickleValue] = [] }
final class PickleDict { var pairs: [(PickleValue, PickleValue)] = [] }

/// Giải mã pickle protocol 2–5, chỉ các opcode xuất hiện trong chỉ mục rpa
/// (dict/list/tuple/str/bytes/int). Opcode khác → lỗi rõ ràng.
enum Pickle {
    static func load(_ data: Data) throws -> PickleValue {
        let bytes = [UInt8](data)
        var pos = 0
        var stack: [PickleValue?] = []   // nil = MARK
        var memo: [Int: PickleValue] = [:]

        func take(_ n: Int) throws -> ArraySlice<UInt8> {
            guard pos + n <= bytes.count else { throw RenPyArchive.ArchiveError.corrupt }
            defer { pos += n }
            return bytes[pos ..< pos + n]
        }
        func uint(_ n: Int) throws -> Int {
            try take(n).reversed().reduce(0) { $0 << 8 | Int($1) }
        }
        func signed(_ slice: ArraySlice<UInt8>) -> Int {
            guard !slice.isEmpty else { return 0 }
            var value = slice.reversed().reduce(0) { $0 << 8 | Int($1) }
            if slice.last! & 0x80 != 0, slice.count < 8 { value -= 1 << (8 * slice.count) }
            return value
        }
        func pop() throws -> PickleValue {
            guard let v = stack.popLast(), let value = v else { throw RenPyArchive.ArchiveError.corrupt }
            return value
        }
        func popToMark() throws -> [PickleValue] {
            guard let mark = stack.lastIndex(where: { $0 == nil }) else { throw RenPyArchive.ArchiveError.corrupt }
            let items = stack[(mark + 1)...].compactMap { $0 }
            stack.removeSubrange(mark...)
            return items
        }
        func string(_ n: Int) throws -> PickleValue {
            .string(String(decoding: try take(n), as: UTF8.self))
        }

        while pos < bytes.count {
            let op = bytes[pos]
            pos += 1
            switch op {
            case 0x80: _ = try take(1)                                   // PROTO
            case 0x95: _ = try take(8)                                   // FRAME
            case 0x94: if let top = stack.last ?? nil { memo[memo.count] = top }   // MEMOIZE
            case 0x71: let i = try uint(1); if let top = stack.last ?? nil { memo[i] = top }   // BINPUT
            case 0x72: let i = try uint(4); if let top = stack.last ?? nil { memo[i] = top }   // LONG_BINPUT
            case 0x68: stack.append(memo[try uint(1)])                   // BINGET
            case 0x6A: stack.append(memo[try uint(4)])                   // LONG_BINGET
            case 0x28: stack.append(nil)                                 // MARK
            case 0x7D: stack.append(.dict(PickleDict()))                 // EMPTY_DICT
            case 0x5D: stack.append(.list(PickleList()))                 // EMPTY_LIST
            case 0x29: stack.append(.tuple([]))                          // EMPTY_TUPLE
            case 0x4E: stack.append(PickleValue.none)                    // NONE
            case 0x88: stack.append(.bool(true))                         // NEWTRUE
            case 0x89: stack.append(.bool(false))                        // NEWFALSE
            case 0x4B: stack.append(.int(try uint(1)))                   // BININT1
            case 0x4D: stack.append(.int(try uint(2)))                   // BININT2
            case 0x4A: stack.append(.int(signed(try take(4))))           // BININT
            case 0x8A: let n = try uint(1); stack.append(.int(signed(try take(n))))   // LONG1
            case 0x8B: let n = try uint(4); stack.append(.int(signed(try take(n))))   // LONG4
            case 0x8C: stack.append(try string(try uint(1)))             // SHORT_BINUNICODE
            case 0x58: stack.append(try string(try uint(4)))             // BINUNICODE
            case 0x8D: stack.append(try string(try uint(8)))             // BINUNICODE8
            case 0x43, 0x55: stack.append(.bytes(Data(try take(try uint(1)))))   // SHORT_BINBYTES / SHORT_BINSTRING
            case 0x42, 0x54: stack.append(.bytes(Data(try take(try uint(4)))))   // BINBYTES / BINSTRING
            case 0x8E: stack.append(.bytes(Data(try take(try uint(8)))))         // BINBYTES8
            case 0x85: stack.append(.tuple([try pop()]))                 // TUPLE1
            case 0x86: let b = try pop(), a = try pop(); stack.append(.tuple([a, b]))           // TUPLE2
            case 0x87: let c = try pop(), b = try pop(), a = try pop(); stack.append(.tuple([a, b, c]))   // TUPLE3
            case 0x74: stack.append(.tuple(try popToMark()))             // TUPLE
            case 0x61:                                                   // APPEND
                let item = try pop()
                guard case .list(let list) = try pop() else { throw RenPyArchive.ArchiveError.corrupt }
                list.items.append(item)
                stack.append(.list(list))
            case 0x65:                                                   // APPENDS
                let items = try popToMark()
                guard case .list(let list) = try pop() else { throw RenPyArchive.ArchiveError.corrupt }
                list.items += items
                stack.append(.list(list))
            case 0x73:                                                   // SETITEM
                let value = try pop(), key = try pop()
                guard case .dict(let dict) = try pop() else { throw RenPyArchive.ArchiveError.corrupt }
                dict.pairs.append((key, value))
                stack.append(.dict(dict))
            case 0x75:                                                   // SETITEMS
                let items = try popToMark()
                guard case .dict(let dict) = try pop() else { throw RenPyArchive.ArchiveError.corrupt }
                var i = 0
                while i + 1 < items.count { dict.pairs.append((items[i], items[i + 1])); i += 2 }
                stack.append(.dict(dict))
            case 0x2E: return try pop()                                  // STOP
            default: throw RenPyArchive.ArchiveError.unsupportedPickle(op)
            }
        }
        throw RenPyArchive.ArchiveError.corrupt
    }
}
