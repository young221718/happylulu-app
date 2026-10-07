import AppKit
import Foundation
@preconcurrency import Sparkle

func L(_ ko: String, _ en: String) -> String { en }
func require(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let domain = Bundle.main.bundleIdentifier!
defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
let host = Bundle.main
let driver = SPUStandardUserDriver(hostBundle: host, delegate: nil)
let engine = SPUUpdater(hostBundle: host, applicationBundle: host, userDriver: driver, delegate: nil)
engine.automaticallyChecksForUpdates = true
engine.automaticallyDownloadsUpdates = true
let model = AppUpdater()
for selector in ["updater:willInstallUpdateOnQuit:immediateInstallationBlock:", "updater:didAbortWithError:", "updater:didFinishUpdateCycleForUpdateCheck:error:"] {
    require(model.responds(to: NSSelectorFromString(selector)), "Missing Sparkle ObjC delegate selector: " + selector)
}
let item = SUAppcastItem(dictionary: ["title": "Fixture", "enclosure": ["url": "https://example.invalid/update.zip", "sparkle:version": "2", "length": "1"]])!
var installed = 0
model.canInstallNow = { false }
require(model.updater(engine, willInstallUpdateOnQuit: item, immediateInstallationBlock: { installed += 1 }), "Prepared update must retain callback")
require(model.isPreparingInstallation, "Prepared update locks settings")
model.setAutomaticallyChecks(false)
model.setAutomaticallyInstalls(false)
require(engine.automaticallyChecksForUpdates && engine.automaticallyDownloadsUpdates, "Locked setters must not strand the cycle")
model.installWhenIdle()
require(installed == 0, "Busy app must not install")
model.canInstallNow = { true }
model.installWhenIdle()
require(installed == 1, "Idle app must install")
model.installWhenIdle()
require(installed == 1, "In-flight installation must not be invoked twice")
model.installationWasDeferred()
model.installWhenIdle()
require(installed == 2, "Confirmed canceled termination leaves a retry callback")
model.updater(engine, didAbortWithError: NSError(domain: "Test", code: 1))
require(!model.isPreparingInstallation, "Aborted installation must unlock settings")
model.installWhenIdle()
require(installed == 2, "Abort clears pending callback")
model.setAutomaticallyChecks(false)
model.setAutomaticallyInstalls(false)
require(!engine.automaticallyChecksForUpdates && !engine.automaticallyDownloadsUpdates, "Settings must work after abort")
require(!model.updater(engine, willInstallUpdateOnQuit: item, immediateInstallationBlock: { installed += 1 }), "Disabled auto install must leave Sparkle in control")
print("PASS actual AppUpdater: busy/idle gate, prepared settings lock, canceled-termination retry, abort cleanup, opt-out")

model.setAutomaticallyChecks(true)
model.setAutomaticallyInstalls(true)
require(model.updater(engine, willInstallUpdateOnQuit: item, immediateInstallationBlock: { installed += 1 }), "Second preparation")
model.updater(engine, didFinishUpdateCycleFor: .updatesInBackground, error: NSError(domain: "TestAuthorizeLater", code: 2))
require(!model.isPreparingInstallation, "Cycle completion unlocks even errors without abort callback")
model.installWhenIdle()
require(installed == 2, "Cycle completion cancels timer callback")
print("PASS cycle completion cleanup, including authorization deferred")
