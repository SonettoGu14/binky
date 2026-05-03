import Foundation

enum BinkyCLIPaths {

    /// Reads UTF-8 stdin up to ~8 MiB — newline-split, trim, drop empties/# comments.
    static func readPOSIXPathsFromStandardInput(maxBytes: Int = 8_388_608) throws -> [String] {
        let data = FileHandle.standardInput.readData(ofLength: maxBytes)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadUnknownStringEncoding)
        }
        return text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func standardizedFileURLs(posixPaths: [String]) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for raw in posixPaths {
            let expanded = (raw as NSString).expandingTildeInPath
            let u = URL(fileURLWithPath: expanded).standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            out.append(u)
        }
        return out
    }

    nonisolated static func uniqPreservingOrder(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for u in urls {
            let path = u.path
            if seen.insert(path).inserted {
                out.append(u)
            }
        }
        return out
    }
}
