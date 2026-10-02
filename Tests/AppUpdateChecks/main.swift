import AppKit
import CryptoKit
import Foundation
@preconcurrency import Sparkle

func require(_ condition: Bool, _ message: String) {
    if !condition { fatalError(message) }
}

guard CommandLine.arguments.count == 3 else { fatalError("Pass an app bundle and signed appcast (or --configuration-only)") }
let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
let configurationOnly = CommandLine.arguments[2] == "--configuration-only"
let feedURL = URL(fileURLWithPath: CommandLine.arguments[2])
let info = try PropertyListSerialization.propertyList(from: Data(contentsOf:
    appURL.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation:
    Data(base64Encoded: info["SUPublicEDKey"] as! String)!)
require(info["SUAutomaticallyUpdate"] as? Bool == false,
        "Production app must ask before downloading and installing updates")
require(info["SUAllowsAutomaticUpdates"] as? Bool == false,
        "Sparkle must not offer automatic-install opt-in")
if !configurationOnly {
let document = try XMLDocument(contentsOf: feedURL)
let enclosure = try document.nodes(forXPath: "//item/enclosure").first as! XMLElement
let signature = Data(base64Encoded: enclosure.attribute(forName: "sparkle:edSignature")!.stringValue!)!
let downloadURL = URL(string: enclosure.attribute(forName: "url")!.stringValue!)!
let archiveURL = feedURL.deletingLastPathComponent().appendingPathComponent(downloadURL.lastPathComponent)
let archive = try Data(contentsOf: archiveURL)
require(publicKey.isValidSignature(signature, for: archive), "Actual update archive must have a valid signature")
var changed = archive
changed[0] ^= 1
require(!publicKey.isValidSignature(signature, for: changed), "Modified update archives must be rejected")
print("PASS signed archive and tamper rejection")

let feedData = try Data(contentsOf: feedURL)
let marker = Data("<!-- sparkle-signatures:\n".utf8)
let markerRange = feedData.range(of: marker, options: .backwards)!
let payload = Data(feedData[..<markerRange.lowerBound])
let block = String(data: feedData[markerRange.lowerBound...], encoding: .utf8)!
let lines = block.split(separator: "\n")
let feedSignature = Data(base64Encoded: String(lines.first(where: { $0.hasPrefix("edSignature: ") })!.dropFirst(13)))!
let length = Int(lines.first(where: { $0.hasPrefix("length: ") })!.dropFirst(8))!
require(payload.count == length && publicKey.isValidSignature(feedSignature, for: payload),
        "Published appcast content must have a valid signature")
var changedFeed = payload
changedFeed[0] ^= 1
require(!publicKey.isValidSignature(feedSignature, for: changedFeed), "Changed appcast metadata must be rejected")
let notes = try document.nodes(forXPath: "//sparkle:releaseNotesLink").first as! XMLElement
let notesURL = URL(string: notes.stringValue!)!
let notesData = try Data(contentsOf: feedURL.deletingLastPathComponent().appendingPathComponent(notesURL.lastPathComponent))
let notesSignature = Data(base64Encoded: notes.attribute(forName: "sparkle:edSignature")!.stringValue!)!
require(publicKey.isValidSignature(notesSignature, for: notesData), "Published release notes must have a valid signature")
print("PASS signed appcast, metadata tamper rejection and signed release notes")
} else {
    print("SKIP signatures: configuration-only mode; signed feed is not validated")
}

let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HappyLulu-update-check-" + UUID().uuidString)
let testApp = folder.appendingPathComponent("UpdateCheck.app")
let contents = testApp.appendingPathComponent("Contents")
try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
var testInfo = info
let domain = "local.HappyLulu.UpdateCheck." + UUID().uuidString
testInfo["CFBundleIdentifier"] = domain
testInfo["SUDefaultsDomain"] = domain
testInfo["SUEnableAutomaticChecks"] = false
testInfo["SUAutomaticallyUpdate"] = false
try PropertyListSerialization.data(fromPropertyList: testInfo, format: .xml, options: 0)
    .write(to: contents.appendingPathComponent("Info.plist"))
try FileManager.default.createSymbolicLink(at:
    contents.appendingPathComponent("MacOS/HappyLulu"), withDestinationURL:
    appURL.appendingPathComponent("Contents/MacOS/HappyLulu"))
defer {
    UserDefaults.standard.removePersistentDomain(forName: domain)
    try? FileManager.default.removeItem(at: folder)
}
let host = Bundle(url: testApp)!
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let driver = SPUStandardUserDriver(hostBundle: host, delegate: nil)
let updater = SPUUpdater(hostBundle: host, applicationBundle: host, userDriver: driver, delegate: nil)
try updater.start()
require(updater.canCheckForUpdates, "Packaged configuration must start a real Sparkle updater")
require(updater.feedURL?.scheme == "https", "Production feed must use HTTPS")
require(!updater.automaticallyChecksForUpdates && !updater.automaticallyDownloadsUpdates,
        "Settings must honor the isolated user preference defaults")
updater.automaticallyChecksForUpdates = true
updater.automaticallyDownloadsUpdates = true
require(updater.automaticallyChecksForUpdates && !updater.automaticallyDownloadsUpdates,
        "Automatic download opt-in must be disallowed even with automatic checks")
updater.automaticallyChecksForUpdates = false
print("PASS Sparkle startup and confirmation-based update defaults in an isolated domain")
