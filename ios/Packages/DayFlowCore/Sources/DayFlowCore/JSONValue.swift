import Foundation

/// Any JSON value. Files from the Mac app, older versions or a hand-edited file are read into
/// this first and then cleaned field by field, the way src/main.js does it, so a stray value
/// falls back to its starting value instead of failing the whole file.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }

    /// A string as JavaScript's String() would give it, for ids and names.
    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    /// The exact string, or nil for any other kind of value.
    public var string: String? { if case .string(let s) = self { return s }; return nil }

    /// A number as JavaScript's Number() would read it ("12" counts, "abc" doesn't).
    public var numberValue: Double? {
        switch self {
        case .number(let n): return n.isFinite ? n : nil
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return 0 }
            return Double(t).flatMap { $0.isFinite ? $0 : nil }
        case .bool(let b): return b ? 1 : 0
        case .null: return 0
        default: return nil
        }
    }

    /// JavaScript truthiness, used by `!!value`.
    public var truthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n != 0 && !n.isNaN
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }

    public static func decode(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Turns any Encodable model into a JSONValue, for building export files.
    public static func from<T: Encodable>(_ value: T) -> JSONValue {
        guard let data = try? JSONEncoder().encode(value), let v = try? decode(data) else { return .null }
        return v
    }
}

/// Encodes JSON the way the Mac app writes it: two-space indents, keys in a stable order.
public enum JSONFile {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(value)
    }
}
