import Foundation

/// Copies Finder’s Spotlight “Comments” metadata when the user enables “Preserve Finder comments”.
enum FinderCommentsCopier {

    /// Copies the Finder comment extended attribute from `source` to `destination` when present.
    static func copyFinderComment(from source: URL, to destination: URL) {
        copyExtendedAttribute(
            named: "com.apple.metadata:kMDItemFinderComment",
            from: source,
            to: destination
        )
    }

    private static func copyExtendedAttribute(named name: String, from source: URL, to destination: URL) {
        let srcPath = source.path
        let dstPath = destination.path
        name.withCString { cName in
            let size = getxattr(srcPath, cName, nil, 0, 0, 0)
            guard size > 0 else { return }
            var buffer = [UInt8](repeating: 0, count: size)
            let read = buffer.withUnsafeMutableBytes { buf in
                getxattr(srcPath, cName, buf.baseAddress!, size, 0, 0)
            }
            guard read == size else { return }
            buffer.withUnsafeBytes { buf in
                _ = setxattr(dstPath, cName, buf.baseAddress!, size, 0, 0)
            }
        }
    }
}
