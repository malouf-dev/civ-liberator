import Foundation
import Darwin

struct Game {
    let number: String
    var id: String { number == "5" ? "8930" : "289070" }
    var title: String { number == "5" ? "Civilization V" : "Civilization VI" }
    var fullName: String { "Sid Meier's " + title }
    var support: String { number == "5" ? "Sid Meier's Civilization 5" : fullName }
    var executable: String { number == "5" ? "Civilization V" : "Civ6_Exe_Child" }
    var modsFolder: String { number == "5" ? "MODS" : "Mods" }
    // Major expansions only; DLC packs always stay on. id matches the game's InAppPurchaseContent.
    var expansions: [(key: String, id: String, name: String)] {
        number == "5" ? [("godsandkings","dlc_godsandkings","Gods & Kings"),("bravenewworld","dlc_bravenewworld","Brave New World")]
                      : [("riseandfall","riseandfall","Rise and Fall"),("gatheringstorm","gatheringstorm","Gathering Storm")]
    }
}
let spec = Game(number: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "6")
func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of:"'",with:"'\\''") + "'" }
func url(_ s: String) -> URL { URL(fileURLWithPath:(s as NSString).expandingTildeInPath).standardizedFileURL }
let fm = FileManager.default
// Matches liberate.sh: colour only on a terminal, never when NO_COLOR is set.
let colour = isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil && (ProcessInfo.processInfo.environment["TERM"] ?? "dumb") != "dumb"
func heading(_ s: String) -> String { colour ? "\n\u{1b}[1;34m==>\u{1b}[0m \u{1b}[1m\(s)\u{1b}[0m" : "\n==> \(s)" }

// Inspect the directory entry itself: never follow a Steam shortcut into its game.
func targetIdentity(_ target: URL) throws -> String {
    var info = stat()
    if lstat(target.path, &info) != 0 {
        if errno == ENOENT { return "none" }
        throw SetupError("Cannot inspect existing app: \(target.path)")
    }
    return "\(info.st_dev):\(info.st_ino)"
}
func validateReplacement(_ target: URL, approval: String) throws {
    let current = try targetIdentity(target)
    guard current == approval else {
        throw SetupError(current == "none" ? "The existing app changed during setup. Run setup again." : "An app already exists or changed at \(target.path). Confirm replacement in setup, or use --replace with --yes.")
    }
}
func exists(_ p: URL) -> Bool { fm.fileExists(atPath:p.path) || (try? fm.destinationOfSymbolicLink(atPath:p.path)) != nil }
func check(_ source: SteamInstall, folder: URL, data: URL, replacement: String = "none") throws {
    let target = child(folder,spec.fullName + ".app"), home = fm.homeDirectoryForCurrentUser
    guard !within(folder,source.steamapps), !within(data,source.steamapps),
          !within(data,target), !within(target,data), data.path != "/", data != home,
          !within(data,child(home,"Library/Application Support/Steam")),
          !within(data,child(home,"Library/Application Support/" + spec.support)) else { throw SetupError("Choose separate app and data folders outside Steam and existing game data.") }
    try validateReplacement(target, approval: replacement)
    for path in ["Saves","ModdedSaves",spec.modsFolder,"Logs","ModUserData","Cache",".runtime-home",".runtime-home/Library",".runtime-home/Library/Application Support",".runtime-home/tmp"] {
        guard within(child(data,path),data) else { throw SetupError("Data folder contains a link outside itself: \(path)") }
    }
    let file = try run("/usr/bin/file",["-b",child(source.app,"Contents/MacOS/" + spec.executable).path])
    let arm = (try? run("/usr/sbin/sysctl",["-n","hw.optional.arm64"]).trimmingCharacters(in:.whitespacesAndNewlines)) == "1"
    guard file.contains("arm64") || file.contains("x86_64") else { throw SetupError("Only 64-bit native Mac game builds are supported.") }
    if !arm && !file.contains("x86_64") { throw SetupError("This game build does not contain Intel code.") }
    if arm && !file.contains("arm64") { do { _ = try run("/usr/bin/arch",["-x86_64","/usr/bin/true"]) } catch { throw SetupError("This Intel game needs Rosetta 2. Install Rosetta, then retry.") } }
    if let info = NSDictionary(contentsOf:child(source.app,"Contents/Info.plist")), let minimum = info["LSMinimumSystemVersion"] as? String {
        let v=ProcessInfo.processInfo.operatingSystemVersion
        if "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)".compare(minimum,options:.numeric) == .orderedAscending { throw SetupError("This game needs macOS \(minimum) or newer.") }
    }
}
func verifyDependencies(_ root: URL) throws {
    let map = try JSONDecoder().decode([String:String].self,from:Data(contentsOf:child(root,"dependencies/checksums.json")))
    for (path,hash) in map {
        let file=child(root,path)
        guard within(file,root),sha(try Data(contentsOf:file)) == hash else { throw SetupError("Dependency checksum mismatch: \(path)") }
    }
}
// Expansions the Steam manifest owns, as "key<TAB>name" lines for liberate.sh.
func installedExpansions(_ source: SteamInstall) -> [String] {
    let owned = Set(matches("\"dlcappid\"\\s+\"(\\d+)\"", source.manifest).map { $0[1] })
    let content = (NSDictionary(contentsOf:child(source.app,"Contents/Info.plist"))?["InAppPurchaseContent"] as? [[String: Any]]) ?? []
    return spec.expansions.filter { e in content.contains { $0["id"] as? String == e.id && !steamIDs($0).isDisjoint(with: owned) } }.map { "\($0.key)\t\($0.name)" }
}
func expansionIDs(_ list: String) throws -> Set<String> {
    Set(try list.split(separator: ",").map { key in
        guard let e = spec.expansions.first(where: { $0.key == key }) else { throw SetupError("Unknown expansion: \(key)") }
        return e.id
    })
}
// --manage: rewrite the owned-content lists inside an existing copy and re-sign it, without rebuilding.
func setExpansions(app: URL, source: SteamInstall, without: String) throws {
    let off = try expansionIDs(without)
    let game = child(app,"Contents/Helpers/Game.app"), settings = child(game,"Contents/MacOS/steam_settings"), record = child(app,"Contents/Resources/civ-liberator.json")
    guard var choices = (try? JSONSerialization.jsonObject(with: Data(contentsOf: record))) as? [String: Any], fm.fileExists(atPath: settings.path) else { throw SetupError("This app was not made by Civ Liberator setup.") }
    // Re-signing a running game can crash it; lsof exits 0 only when something has the executable open.
    if (try? run("/usr/sbin/lsof",["-t",child(game,"Contents/MacOS/"+spec.executable).path])) != nil { throw SetupError("Quit \(spec.title) first, then run --manage again.") }
    let content = (NSDictionary(contentsOf:child(game,"Contents/Info.plist"))?["InAppPurchaseContent"] as? [[String: Any]]) ?? []
    print("    Updating the expansion list");fflush(stdout)
    try writeOwnedContent(manifest: source.manifest, content: content, without: off, to: settings)
    choices["without"] = without
    try JSONSerialization.data(withJSONObject: choices).write(to: record, options: .atomic)
    print("    Signing the app");fflush(stdout)
    do {
        for bundle in [game, app] { try run("/usr/bin/codesign",["--force","--deep","--sign","-",bundle.path]) }
        try run("/usr/bin/codesign",["--verify","--deep","--strict",app.path])
    } catch { throw SetupError("Signing did not finish, so the app may not open. Run --manage again to retry.\n\(error.localizedDescription)") }
    print(heading("\(spec.title) is ready") + "\n    Open: \((app.path as NSString).abbreviatingWithTildeInPath)")
}
func install(root: URL, source: SteamInstall, folder: URL, data: URL, menus: Bool, mods: Bool, replacement: String = "none", without: String = "") throws {
    let off=try expansionIDs(without);try check(source,folder:folder,data:data,replacement:replacement);try verifyDependencies(root)
    try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    guard fm.isWritableFile(atPath:folder.path) else { throw SetupError("Destination is not writable. Choose ~/Applications; do not run with sudo.") }
    let stage=child(folder,".civ-liberator-" + UUID().uuidString)
    try fm.createDirectory(at:stage,withIntermediateDirectories:false)
    defer { try? fm.removeItem(at:stage) }
    let app=child(stage,spec.fullName + ".app"), resources=child(app,"Contents/Resources"),mac=child(app,"Contents/MacOS"),kit=child(resources,"Kit")
    try fm.createDirectory(at:kit,withIntermediateDirectories:true);try fm.createDirectory(at:mac,withIntermediateDirectories:true)
    for name in ["libsteam_api.dylib","Goldberg-LICENSE.txt","GPL-3.0.txt"] { try fm.copyItem(at:child(root,"dependencies/"+name),to:child(kit,name)) }
    try fm.copyItem(at:child(root,"dependencies/menus-\(spec.number).json"),to:child(kit,"offline-ui.json"))
    let home=child(data,".runtime-home")
    let script = """
    #!/bin/bash
    set -e
    base="$(cd "$(dirname "$0")/.." && pwd)"
    export HOME=\(quote(home.path))
    export CFFIXED_USER_HOME="$HOME"
    export XDG_DATA_HOME="$HOME/Library/Application Support"
    export TMPDIR="$HOME/tmp"
    mkdir -p "$TMPDIR"
    unset SteamAppId SteamGameId SteamEnv
    cd "$base/Helpers/Game.app/Contents/MacOS"
    exec \(quote("./"+spec.executable)) >> \(quote(child(data,"Launcher.log").path)) 2>&1
    """
    let launch=child(mac,"Launch");try script.write(to:launch,atomically:true,encoding:.utf8);try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:launch.path)
    var info:[String:Any] = ["CFBundleName":spec.fullName,"CFBundleDisplayName":spec.fullName,"CFBundleIdentifier":"local.civliberator.civ"+spec.number,"CFBundleExecutable":"Launch","CFBundlePackageType":"APPL","CFBundleVersion":"2","LSMinimumSystemVersion":"11.0"]
    if let original=NSDictionary(contentsOf:child(source.app,"Contents/Info.plist")),var icon=original["CFBundleIconFile"] as? String, !icon.contains("/") {
        if !icon.hasSuffix(".icns") { icon += ".icns" }
        let file=child(source.app,"Contents/Resources/"+icon)
        if fm.fileExists(atPath:file.path) { try fm.copyItem(at:file,to:child(resources,icon)); info["CFBundleIconFile"]=icon }
    }
    try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:child(app,"Contents/Info.plist"))
    // Every setup choice, so liberate.sh --manage can rebuild without asking again.
    let choices=["game":spec.number,"data":data.path,"source":source.app.path,"menus":menus ? "yes":"no","mods":mods ? "yes":"no","without":without]
    try JSONSerialization.data(withJSONObject:choices).write(to:child(resources,"civ-liberator.json"))
    let builder=Builder(app:app)
    let tty = isatty(STDOUT_FILENO) != 0
    var prior = "",last = -1,open = false
    // One line per phase; on a terminal the copy bar redraws in place until 100%.
    builder.updates = { update in
        if update.title != prior {
            if open { print("");open=false }
            print("    " + (update.detail.isEmpty || update.total != nil ? update.title : update.title + ". " + update.detail));prior=update.title
        }
        if let done=update.completed, let total=update.total,total>0 {
            let percent=Int(Double(done)/Double(total)*100)
            if percent != last {
                let filled=percent/5
                let bar=String(repeating:"=",count:filled)+String(repeating:" ",count:20-filled)
                let line=String(format:"    [%@] %3d%%  %.2f / %.2f GB",bar,percent,Double(done)/1e9,Double(total)/1e9)
                if tty { print("\r\u{1b}[2K"+line,terminator:percent == 100 ? "\n":"");open = percent != 100 } else if percent % 10 == 0 || percent == 100 { print(line) }
                last=percent
            }
        }
        fflush(stdout)
    }
    do { _ = try builder.build(install:source,data:data,offline:menus,mods:mods,without:off) } catch { if open { print("") };throw error }
    let target=child(folder,spec.fullName+".app")
    var backup: URL?
    try validateReplacement(target, approval: replacement)
    if exists(target) {
        let saved=child(folder,".civ-liberator-backup-"+UUID().uuidString+".app")
        try fm.moveItem(at:target,to:saved);backup=saved
    }
    if renamex_np(app.path,target.path,UInt32(RENAME_EXCL)) != 0 {
        if let backup, !exists(target) { try? fm.moveItem(at:backup,to:target) }
        throw SetupError("Cannot publish the app without replacing another item.")
    }
    let short = { (url: URL) in (url.path as NSString).abbreviatingWithTildeInPath }
    // Lines under a ==> heading are indented to match liberate.sh.
    print(heading("\(spec.title) is ready") + "\n    Open: \(short(target))\n    Saves and mods: \(short(data))")
    if let backup { print("    Previous app backup: \(short(backup))") }
    if mods { print("    Enable copied mods in the game\'s " + (spec.number == "6" ? "Additional Content" : "Mods") + " menu.") }
}
@main struct Main {
 static func main() {
  do {
   let args=CommandLine.arguments
   guard args.count>=3,["5","6"].contains(args[2]),geteuid() != 0 else { throw SetupError("Use liberate.sh as your normal user.") }
   switch args[1] {
   case "discover": for game in SteamInstall.discover(home:fm.homeDirectoryForCurrentUser) { print(game.app.path) }
   case "target-identity":
    guard args.count==4 else { throw SetupError("Invalid destination arguments") };print(try targetIdentity(child(url(args[3]),spec.fullName+".app")))
   case "check": guard [6,7].contains(args.count) else { throw SetupError("Invalid preflight arguments") };try check(SteamInstall.from(url(args[3])),folder:url(args[4]),data:url(args[5]),replacement:args.count==7 ? args[6] : "none")
   case "build": guard (9...11).contains(args.count) else { throw SetupError("Invalid build arguments") };try install(root:url(args[3]),source:SteamInstall.from(url(args[4])),folder:url(args[5]),data:url(args[6]),menus:args[7]=="yes",mods:args[8]=="yes",replacement:args.count>=10 ? args[9] : "none",without:args.count==11 ? args[10] : "")
   case "set-expansions": guard args.count==6 else { throw SetupError("Invalid expansion arguments") };try setExpansions(app:url(args[3]),source:SteamInstall.from(url(args[4])),without:args[5])
   case "expansions": guard args.count==4 else { throw SetupError("Invalid expansion arguments") };for line in installedExpansions(try SteamInstall.from(url(args[3]))) { print(line) }
   case "verify-menus":
    guard args.count==5 else { throw SetupError("Invalid menu verification arguments") }
    let patches=try JSONDecoder().decode([Patch].self,from:Data(contentsOf:url(args[3])))
    let source=url(args[4])
    for patch in patches {
        let file=child(source,patch.path)
        guard within(file,source) else { throw SetupError("Invalid menu path") }
        _ = try patchedMenu(Data(contentsOf:file),patch:patch)
    }
    print("Verified \(patches.count) menu patches for Civ \(spec.number)")
   case "manifest":
    guard args.count==4 else { throw SetupError("Invalid manifest arguments") }
    let root=url(args[3]);var map=[String:String]()
    for name in ["menus-5.json","menus-6.json","goldberg-build.patch","Goldberg-LICENSE.txt","GPL-3.0.txt","libsteam_api.dylib","source/goldberg-2ad4a39.tar.gz","source/protobuf-23.1-with-abseil.tar.gz"] { let path="dependencies/"+name;map[path]=sha(try Data(contentsOf:child(root,path))) }
    try JSONSerialization.data(withJSONObject:map,options:[.prettyPrinted,.sortedKeys]).write(to:child(root,"dependencies/checksums.json"),options:.atomic)
   case "verify":guard args.count==4 else { throw SetupError("Invalid verification arguments") };try verifyDependencies(url(args[3]));print("Dependencies verified")
   default:throw SetupError("Unknown command")
   }
  } catch { fputs((colour ? "\u{1b}[1;31mError:\u{1b}[0m " : "Error: ") + error.localizedDescription + "\n",stderr);exit(1) }
 }
}
