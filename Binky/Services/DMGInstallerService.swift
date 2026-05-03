import Foundation

/// Mounts a DMG read-only, copies top-level `.app` bundles to an Applications folder, detaches, returns installed URLs.
enum DMGInstallerService: Sendable {

    enum InstallError: Error {
        case hdiutilFailed(Int32)
        case noMountPoint
        case noAppFound
        case copyFailed(String)
    }

    static func installApps(fromDmg dmg: URL, applicationsDestination: URL) throws -> [URL] {
        let fm = FileManager.default
        let plistData = try attachPlist(for: dmg)
        guard let mountPoint = parseMountPoint(fromPlistData: plistData) else {
            throw InstallError.noMountPoint
        }
        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint, "-force"]
            try? detach.run()
            detach.waitUntilExit()
        }

        let mountURL = URL(fileURLWithPath: mountPoint, isDirectory: true)
        let appBundles = try fm.contentsOfDirectory(at: mountURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "app" }

        guard !appBundles.isEmpty else {
            throw InstallError.noAppFound
        }

        try fm.createDirectory(at: applicationsDestination, withIntermediateDirectories: true)

        var installed: [URL] = []
        for appURL in appBundles {
            let dest = applicationsDestination.appendingPathComponent(appURL.lastPathComponent, isDirectory: true)
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            do {
                try fm.copyItem(at: appURL, to: dest)
                installed.append(dest)
            } catch {
                throw InstallError.copyFailed(error.localizedDescription)
            }
        }
        return installed
    }

    private static func attachPlist(for dmg: URL) throws -> Data {
        let p = Process()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["attach", "-plist", "-nobrowse", "-readonly", dmg.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw InstallError.hdiutilFailed(p.terminationStatus)
        }
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }

    private static func parseMountPoint(fromPlistData data: Data) -> String? {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }
        if let dict = obj as? [String: Any] {
            if let arr = dict["system-entities"] as? [[String: Any]] {
                for row in arr {
                    if let mp = row["mount-point"] as? String {
                        return mp
                    }
                }
            }
        }
        if let arr = obj as? [[String: Any]] {
            for row in arr {
                if let mp = row["mount-point"] as? String ?? row["MountPoint"] as? String {
                    return mp
                }
            }
        }
        return nil
    }
}
