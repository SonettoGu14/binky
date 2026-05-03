import BinkyCoreShared
import Foundation

enum PrettyJSON {
    nonisolated static func encode<T: Encodable>(_ value: T) -> Data? {
        let enc = JSONEncoder()
        if #available(macOS 10.15, *) {
            enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        }
        return try? enc.encode(value)
    }

    nonisolated static func encodeString<T: Encodable>(_ value: T) -> String? {
        guard let bytes = encode(value) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }
}

enum BinkyCLIPrint {
    nonisolated static func err(_ line: String) {
        fputs("\(line)\n", stderr)
    }

    /// Machine-readable payloads go to stdout; anything human goes to stderr (so pipes stay pure JSON).
    nonisolated static func jsonLine<T: Encodable>(_ payload: T) {
        guard let text = PrettyJSON.encodeString(payload) else { return }
        print(text)
        fflush(stdout)
    }
}
