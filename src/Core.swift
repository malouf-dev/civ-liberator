import Foundation
import CryptoKit
import Darwin

struct SetupError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

func matches(_ pattern: String, _ text: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
        (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }
}

func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func child(_ url: URL, _ path: String) -> URL { url.appendingPathComponent(path) }
func within(_ url: URL, _ parent: URL) -> Bool {
    let a = url.resolvingSymlinksInPath().standardizedFileURL.path
    let b = parent.resolvingSymlinksInPath().standardizedFileURL.path
    return a == b || a.hasPrefix(b + "/")
}

@discardableResult func run(_ executable: String, _ args: [String]) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    process.standardOutput = pipe; process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else { throw SetupError("\(URL(fileURLWithPath: executable).lastPathComponent) failed:\n\(output.suffix(1800))") }
    return output
}

struct SteamInstall {
    let app: URL
    let steamapps: URL
    let manifest: String
    static func from(_ app: URL) throws -> SteamInstall {
        let fm = FileManager.default
        let steamapps = app.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifestURL = child(steamapps, "appmanifest_\(spec.id).acf")
        guard fm.fileExists(atPath: child(app, "Contents/MacOS/\(spec.executable)").path),
              fm.fileExists(atPath: child(app, "Contents/MacOS/libsteam_api.dylib").path),
              let text = try? String(contentsOf: manifestURL, encoding: .utf8),
              !matches("\"appid\"\\s+\"\(spec.id)\"", text).isEmpty else {
            throw SetupError("Choose the native game .app inside a completed Steam installation of \(spec.title).")
        }
        let flags = matches("\"StateFlags\"\\s+\"(\\d+)\"", text).first.flatMap { Int($0[1]) } ?? 0
        guard flags & 4 != 0 else { throw SetupError("Steam has not finished installing this game. Finish the installation, then try again.") }
        return SteamInstall(app: app, steamapps: steamapps, manifest: text)
    }
    static func discover(home: URL) -> [SteamInstall] {
        let root = child(home, "Library/Application Support/Steam")
        var libraries = [root]
        if let text = try? String(contentsOf: child(root, "steamapps/libraryfolders.vdf"), encoding: .utf8) {
            for entry in matches("\"path\"\\s+\"((?:\\\\.|[^\"])*)\"", text) {
                let path = entry[1].replacingOccurrences(of: "\\\\", with: "\\").replacingOccurrences(of: "\\\"", with: "\"")
                let url = URL(fileURLWithPath: path)
                if !libraries.contains(url) { libraries.append(url) }
            }
        }
        return libraries.compactMap { library in
            let steamapps = child(library, "steamapps")
            guard let text = try? String(contentsOf: child(steamapps, "appmanifest_\(spec.id).acf"), encoding: .utf8),
                  let directory = matches("\"installdir\"\\s+\"([^\"]+)\"", text).first?[1] else { return nil }
            let folder = child(steamapps, "common/" + directory)
            let candidates = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return candidates.filter { $0.pathExtension == "app" }.compactMap { try? from($0) }.first
        }
    }
}

struct Edit: Codable { let offset: Int; let length: Int; let text: String }
struct Patch: Codable { let path: String; let before: String; let after: String; let edits: [Edit] }
struct Configuration: Codable {
    let dataDirectory: String
    let offlineMenus: Bool
    let copiedMods: [String]
    let created: Date
    let format: Int
}

struct InstallUpdate {
    let phase: Int
    let title: String
    var detail: String = ""
    var completed: Int64? = nil
    var total: Int64? = nil
}

final class Builder {
    let app: URL
    let resources: URL
    let home: URL
    let fm = FileManager.default
    var progress: (String) -> Void = { _ in }
    var updates: (InstallUpdate) -> Void = { _ in }
    var game: URL { child(app, "Contents/Helpers/Game.app") }
    var configURL: URL { child(resources, "standalone.json") }
    init(app: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.app = app; self.resources = child(app, "Contents/Resources"); self.home = home
    }
    func configuration() throws -> Configuration? {
        guard fm.fileExists(atPath: configURL.path) else { return nil }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
        guard config.format == 1, fm.isExecutableFile(atPath: child(game, "Contents/MacOS/\(spec.executable)").path) else {
            throw SetupError("The embedded game is incomplete. Restore the app from a backup, or build a fresh copy using the setup app.")
        }
        return config
    }
    func write(_ text: String, to url: URL) throws { try Data(text.utf8).write(to: url, options: .atomic) }
    func mkdir(_ url: URL) throws { try fm.createDirectory(at: url, withIntermediateDirectories: true) }

    func copyGame(from source: URL, to destination: URL) throws {
        updates(InstallUpdate(phase: 0, title: "Checking your game", detail: ""))
        var enumerationError: Error?
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], errorHandler: { _, error in enumerationError = error; return false }) else { throw SetupError("Cannot read the installed game.") }
        var entries: [(URL, String, Bool, Bool, Int64)] = []
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            let relative = String(file.path.dropFirst(source.path.count + 1))
            let link = values.isSymbolicLink == true
            if link && !within(file, source) { throw SetupError("The Steam game contains an external link: \(relative). A fully independent copy cannot be made safely.") }
            let size = values.isDirectory == true || link ? 0 : Int64(values.fileSize ?? 0)
            entries.append((file, relative, values.isDirectory == true, link, size)); total += size
        }
        if let enumerationError { throw enumerationError }
        guard !entries.isEmpty else { throw SetupError("The game folder is empty or unreadable.") }
        try mkdir(destination)
        var done: Int64 = 0
        var last = Date.distantPast
        for (index, entry) in entries.enumerated() {
            let (file, relative, directory, link, size) = entry
            let target = child(destination, relative)
            try mkdir(target.deletingLastPathComponent())
            if link {
                // Rewrite absolute internal links to point into the new game.
                let resolved = file.resolvingSymlinksInPath()
                let suffix = String(resolved.path.dropFirst(source.resolvingSymlinksInPath().path.count + 1))
                let original = try fm.destinationOfSymbolicLink(atPath: file.path)
                if original.hasPrefix("/") { throw SetupError("Absolute game link needs a portable replacement: \(suffix)") }
                try fm.createSymbolicLink(atPath: target.path, withDestinationPath: original)
            } else if directory {
                try mkdir(target)
            } else {
                // COPYFILE_CLONE uses independent APFS clones where possible and
                // falls back to a normal copy on other filesystems.
                guard copyfile(file.path, target.path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE)) == 0 else {
                    throw SetupError("Could not copy \(relative): \(String(cString: strerror(errno)))")
                }
            }
            done += size
            if Date().timeIntervalSince(last) > 0.12 || index == entries.count - 1 {
                updates(InstallUpdate(phase: 1, title: "Copying the game", detail: "\(index + 1) of \(entries.count) items • \(relative)", completed: done, total: total))
                last = Date()
            }
        }
    }

    func applyPatches(to game: URL, validateOnly: Bool = false) throws {
        let patches = try JSONDecoder().decode([Patch].self, from: Data(contentsOf: child(resources, "Kit/offline-ui.json")))
        for patch in patches {
            let file = child(game, patch.path)
            guard within(file, game) else { throw SetupError("Invalid UI patch path.") }
            let data = try Data(contentsOf: file)
            guard sha(data) == patch.before else {
                throw SetupError("This game update differs from the tested offline-menu version (\(file.lastPathComponent)). Choose no for hiding online menus, or run with --no-menus.")
            }
            let output = try patchedMenu(data, patch: patch)
            if !validateOnly { try output.write(to: file, options: .atomic) }
        }
    }

    func prepareData(_ directory: URL) throws -> URL {
        try mkdir(directory)
        let privateHome = child(directory, ".runtime-home")
        let support = child(privateHome, "Library/Application Support/\(spec.support)")
        if spec.number == "6" { try mkdir(support) }
        for name in ["Saves", "ModdedSaves", spec.modsFolder, "Logs", "ModUserData", "Cache"] { try mkdir(child(directory, name)) }
        // Redirect only links under our private home, never the user's real Library.
        let links = spec.number == "5" ? [support: directory] : [
            child(support, "\(spec.support)"): directory,
            child(support, "Firaxis Games/\(spec.support)/Logs"): child(directory, "Logs")
        ]
        for (link, destination) in links {
            try mkdir(link.deletingLastPathComponent())
            if let existing = try? fm.destinationOfSymbolicLink(atPath: link.path) {
                guard existing == destination.path else { throw SetupError("The runtime folder points to a different data directory: \(link.path)") }
            } else if fm.fileExists(atPath: link.path) {
                throw SetupError("The runtime folder already contains conflicting data: \(link.path)")
            } else { try fm.createSymbolicLink(atPath: link.path, withDestinationPath: destination.path) }
        }
        try write("\(spec.title) standalone data\nSaves and Mods are in this folder. Keep .runtime-home: it isolates this game's preferences and runtime files from Steam.\n", to: child(directory, "Standalone Data.txt"))
        return privateHome
    }

    func importMods(install: SteamInstall, destination: URL) throws -> [String] {
        let local = child(home, spec.number == "5" ? "Library/Application Support/\(spec.support)/MODS" : "Library/Application Support/\(spec.support)/\(spec.support)/Mods")
        let workshop = child(install.steamapps, "workshop/content/\(spec.id)")
        var seen = Set<String>(), imported = [String]()
        func identity(_ folder: URL) -> String? {
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
                  let info = files.first(where: { $0.pathExtension.lowercased() == "modinfo" }),
                  let text = try? String(contentsOf: info, encoding: .utf8) else { return nil }
            return matches("(?i)<Mod\\s+[^>]*id\\s*=\\s*\"([^\"]+)\"", text).first?[1].lowercased()
        }
        for folder in (try? fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? [] {
            if let id = identity(folder) { seen.insert(id) }
        }
        for source in [local, workshop] {
            for folder in ((try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }) {
                if (try? folder.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == true { throw SetupError("Mod is a symlink: \(folder.path)") }
                guard let id = identity(folder), !seen.contains(id) else { continue }
                // UUID-based names avoid collisions and duplicate Workshop/local copies.
                guard id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { continue }
                let target = child(destination, id)
                guard !fm.fileExists(atPath: target.path) else { continue }
                if let entries = fm.enumerator(at:folder,includingPropertiesForKeys:[.isSymbolicLinkKey]) {
                    for case let entry as URL in entries where (try? entry.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == true { throw SetupError("Mod contains a symlink: \(entry.path)") }
                }
                let temp = child(destination, ".import-" + UUID().uuidString)
                do {
                    try fm.copyItem(at: folder, to: temp)
                    try fm.moveItem(at: temp, to: target)
                } catch {
                    try? fm.removeItem(at: temp)
                    throw error
                }
                seen.insert(id); imported.append(folder.lastPathComponent)
            }
        }
        return imported
    }

    func build(install: SteamInstall, data: URL, offline: Bool, mods: Bool) throws -> Configuration {
        guard !fm.fileExists(atPath: game.path), !fm.fileExists(atPath: configURL.path) else { throw SetupError("This app already contains a game. Use a fresh setup app to rebuild.") }
        guard !within(app, install.steamapps), !within(data, app), !within(app, data),
              !within(data, install.steamapps), !within(data, child(home, "Library/Application Support/Steam")),
              !within(data, child(home, "Library/Application Support/\(spec.support)")) else {
            throw SetupError("Choose a separate data folder outside the app and Steam's game/data folders.")
        }
        guard fm.isWritableFile(atPath: resources.path) else { throw SetupError("Move \(spec.title).app to a writable folder, such as your Applications folder, before building.") }
        if offline { try applyPatches(to: install.app, validateOnly: true) }
        // Verify read/write permissions before copying the large game.
        _ = try prepareData(data)
        let staging = child(resources, ".building-" + UUID().uuidString)
        let stagedGame = child(staging, "Game.app")
        try mkdir(staging)
        defer { try? fm.removeItem(at: staging) }
        var committed = false
        do {
            progress("Copying \(spec.title)… This can take several minutes.")
            try copyGame(from: install.app, to: stagedGame)
            let currentManifest = try String(contentsOf: child(install.steamapps, "appmanifest_\(spec.id).acf"), encoding: .utf8)
            guard currentManifest == install.manifest else { throw SetupError("Steam changed the installation during copying. Let its update finish, then try again.") }
            progress("Preparing the independent game and installed expansions…")
            updates(InstallUpdate(phase: 2, title: "Setting up local play", detail: ""))
            let mac = child(stagedGame, "Contents/MacOS")
            let settings = child(mac, "steam_settings")
            try mkdir(settings)
            for name in ["libsteam_api.dylib", "gglibsteam_api.dylib"] {
                let target = child(mac, name)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: child(resources, "Kit/libsteam_api.dylib"), to: target)
            }
            for (name, value) in ["steam_appid.txt": "\(spec.id)", "force_account_name.txt": "Local Player", "force_language.txt": "english", "offline.txt": "", "disable_networking.txt": ""] {
                try write(value + "\n", to: child(settings, name))
            }
            try write("\(spec.id)\n", to: child(mac, "steam_appid.txt"))
            let interfaces = String(decoding: try Data(contentsOf:child(install.app,"Contents/MacOS/libsteam_api.dylib")), as:UTF8.self).replacingOccurrences(of:"\0",with:"\n")
            let versions = Set(matches("(?m)^(?:Steam[A-Za-z_]+|STEAM[A-Z_]+)\\d{3}$", interfaces).map { $0[0] })
            try write(versions.sorted().joined(separator: "\n") + "\n", to: child(settings, "steam_interfaces.txt"))
            var dlc = Set(matches("\"dlcappid\"\\s+\"(\\d+)\"", install.manifest).map { $0[1] })
            let plistURL = child(stagedGame, "Contents/Info.plist")
            guard var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any] else { throw SetupError("Invalid game Info.plist.") }
            for item in plist["InAppPurchaseContent"] as? [[String: Any]] ?? [] {
                let values = (item["steamID"] as? [Any]) ?? (item["steamID"].map { [$0] } ?? [])
                let ids = Set(values.map { String(describing: $0) })
                if !ids.isDisjoint(with: dlc) { dlc.formUnion(ids) }
            }
            try write(dlc.sorted().map { "\($0)=Installed DLC \($0)" }.joined(separator: "\n") + "\n", to: child(settings, "DLC.txt"))
            let depots = Set(matches("\"(\\d+)\"\\s*\\{\\s*\"manifest\"", install.manifest).map { $0[1] })
            try write(depots.sorted().joined(separator: "\n") + "\n", to: child(settings, "depots.txt"))
            plist["CFBundleName"] = spec.fullName
            plist["CFBundleDisplayName"] = spec.fullName
            // Localized strings override Info.plist in Finder and the running game.
            if let resources = fm.enumerator(at: child(stagedGame, "Contents/Resources"), includingPropertiesForKeys:nil) {
                for case let file as URL in resources where file.lastPathComponent == "InfoPlist.strings" {
                    if var strings = try? PropertyListSerialization.propertyList(from:Data(contentsOf:file),format:nil) as? [String:Any] {
                        strings["CFBundleName"] = spec.fullName
                        strings["CFBundleDisplayName"] = spec.fullName
                        try PropertyListSerialization.data(fromPropertyList:strings,format:.binary,options:0).write(to:file)
                    }
                }
            }
            plist["CFBundleExecutable"] = "\(spec.executable)"
            plist["CFBundleIdentifier"] = "local.civliberator.game\(spec.number)"
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL, options: .atomic)
            if offline { progress("Disabling unsupported menus; keeping expansions, mods and hotseat…"); try applyPatches(to: stagedGame) }
            var imported = [String]()
            updates(InstallUpdate(phase: 3, title: mods ? "Copying your mods" : "Skipping mod copying", detail: mods ? "Your existing mods will be kept." : ""))
            if mods { progress("Copying local and downloaded Workshop mods…"); imported = try importMods(install: install, destination: child(data, spec.modsFolder)) }
            let config = Configuration(dataDirectory: data.path, offlineMenus: offline, copiedMods: imported, created: Date(), format: 1)
            progress("Signing and checking your standalone app…")
            updates(InstallUpdate(phase: 4, title: "Preparing the app to open", detail: "This can take a few minutes."))
            try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", stagedGame.path])
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", stagedGame.path])
            try mkdir(game.deletingLastPathComponent())
            try fm.moveItem(at: stagedGame, to: game)
            committed = true
            // Remove staging before signing the containing app's resource seal.
            try fm.removeItem(at: staging)
            try JSONEncoder().encode(config).write(to: configURL, options: .atomic)
            updates(InstallUpdate(phase: 4, title: "Checking the finished app", detail: ""))
            try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
            return config
        } catch {
            if committed {
                try? fm.removeItem(at: configURL)
                try? fm.removeItem(at: game)
            }
            try? fm.removeItem(at: staging)
            // Restore a valid, retryable bootstrap signature after a failed build.
            _ = try? run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])
            throw error
        }
    }

    func launch(_ config: Configuration) throws -> Process {
        let data = URL(fileURLWithPath: config.dataDirectory)
        guard fm.fileExists(atPath: data.path) else { throw SetupError("Your data folder is unavailable: \(data.path). Reconnect its drive or restore it, then reopen the app.") }
        let privateHome = try prepareData(data)
        let process = Process()
        process.executableURL = child(game, "Contents/MacOS/\(spec.executable)")
        process.currentDirectoryURL = child(game, "Contents/MacOS")
        var env = ProcessInfo.processInfo.environment
        // These values apply only to this child process.
        env["HOME"] = privateHome.path
        env["CFFIXED_USER_HOME"] = privateHome.path
        env["XDG_DATA_HOME"] = child(privateHome, "Library/Application Support").path
        let temp = child(privateHome, "tmp"); try mkdir(temp)
        env["TMPDIR"] = temp.path + "/"
        for key in ["SteamAppId", "SteamGameId", "SteamOverlayGameId", "SteamClientLaunch", "SteamEnv"] { env.removeValue(forKey: key) }
        process.environment = env
        // The game clears its Logs directory at startup. Keep our diagnostic
        // stream outside it so the named log survives a launch.
        let log = child(data, "Launcher.log")
        if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: log)
        try handle.truncate(atOffset: 0)
        process.standardOutput = handle; process.standardError = handle
        try process.run()
        try? handle.close()
        return process
    }
}

// Offsets refer to the exact input digest. No original game source is bundled.
func patchedMenu(_ input: Data, patch: Patch) throws -> Data {
    guard sha(input) == patch.before else { throw SetupError("Unsupported menu version: \(patch.path)") }
    var previousEnd = 0
    for edit in patch.edits {
        guard edit.offset >= previousEnd, edit.offset <= input.count,
              edit.length >= 0, edit.length <= input.count - edit.offset else {
            throw SetupError("Invalid menu edit bounds: \(patch.path)")
        }
        previousEnd = edit.offset + edit.length
    }
    var output = input
    for edit in patch.edits.reversed() {
        output.replaceSubrange(edit.offset..<(edit.offset + edit.length), with: edit.text.utf8)
    }
    guard sha(output) == patch.after else { throw SetupError("Menu verification failed: \(patch.path)") }
    return output
}
