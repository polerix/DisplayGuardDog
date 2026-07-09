import AppKit
import ServiceManagement
import UserNotifications

let agentLabel = "com.polerix.display-watchdog"
let plistPath = NSString(string: "~/Library/LaunchAgents/com.polerix.display-watchdog.plist").expandingTildeInPath

let displayManagerDir = NSString(string: "~/.display-manager").expandingTildeInPath
let watchdogLogPath = displayManagerDir + "/watchdog.log"
let savedConfigPath = displayManagerDir + "/saved-config.txt"
let notifyOffsetStatePath = displayManagerDir + "/menubar-notify-offset.txt"

func currentUID() -> String {
    String(getuid())
}

func isWatchdogRunning() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["list", agentLabel]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        return false
    }
}

@discardableResult
func runLaunchctl(_ args: [String]) -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = args
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus
    } catch {
        return -1
    }
}

func enableWatchdog() {
    runLaunchctl(["bootstrap", "gui/\(currentUID())", plistPath])
}

func disableWatchdog() {
    runLaunchctl(["bootout", "gui/\(currentUID())/\(agentLabel)"])
}

struct ProcessResult {
    let status: Int32
    let output: String
}

// Runs a shell script bundled inside Contents/Resources/Scripts/, so the
// app is self-contained and doesn't depend on anything outside the bundle.
func runBundledScript(_ resourceName: String) -> ProcessResult {
    guard let url = Bundle.main.url(forResource: resourceName, withExtension: "sh", subdirectory: "Scripts") else {
        return ProcessResult(status: -1, output: "Bundled script '\(resourceName).sh' not found.")
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/bash")
    task.arguments = [url.path]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessResult(status: task.terminationStatus, output: output)
    } catch {
        return ProcessResult(status: -1, output: error.localizedDescription)
    }
}

// Mirrors the resolution order used by the bundled bash scripts, so the
// app can warn the user *before* enabling a LaunchAgent that's doomed to
// fail for lack of this dependency.
func resolveDisplayplacer() -> String? {
    for candidate in ["/opt/homebrew/bin/displayplacer", "/usr/local/bin/displayplacer"] {
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    task.arguments = ["displayplacer"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    } catch {
        return nil
    }
}

// Counts displays in the *current* live arrangement, for the Update Saved
// Layout confirmation preview. Returns nil if displayplacer isn't
// available or its output can't be parsed.
func countCurrentDisplays() -> Int? {
    guard let bin = resolveDisplayplacer() else { return nil }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: bin)
    task.arguments = ["list"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, let output = String(data: data, encoding: .utf8) else { return nil }
        let count = output.components(separatedBy: "\n").filter { $0.hasPrefix("Persistent screen id:") }.count
        return count > 0 ? count : nil
    } catch {
        return nil
    }
}

// Counts displays recorded in the last-saved layout, so we can warn when
// the live count has dropped (a display looks disconnected).
func countSavedDisplays() -> Int? {
    guard let contents = try? String(contentsOfFile: savedConfigPath, encoding: .utf8) else { return nil }
    let count = contents.components(separatedBy: "\n").filter { $0.hasPrefix("Persistent screen id:") }.count
    return count > 0 ? count : nil
}

// MARK: - Menu bar icon: hand-drawn pixel-art dog-in-a-square (bundled PNGs),
// standing when the watchdog is on, resting when it's off. These are
// literal bicolor artwork (opaque black square + opaque white dog), not
// template/alpha-masked, so they render as-drawn in both light and dark
// menu bars.

let watchdogIconPointSize = NSSize(width: 18, height: 18)

func loadWatchdogIcon(resourceName: String) -> NSImage {
    guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
          let image = NSImage(contentsOf: url) else {
        return NSImage(size: watchdogIconPointSize)
    }
    image.size = watchdogIconPointSize
    image.isTemplate = false
    return image
}

let watchdogIconOn = loadWatchdogIcon(resourceName: "WatchDog_ON")
let watchdogIconOff = loadWatchdogIcon(resourceName: "WatchDog_OFF")

func makeWatchdogIcon(active: Bool) -> NSImage {
    active ? watchdogIconOn : watchdogIconOff
}

let watchdogNotifyIcon: NSImage = {
    let image = loadWatchdogIcon(resourceName: "WatchDog_Notify")
    image.size = NSSize(width: 64, height: 64)
    return image
}()

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let toggleItem = NSMenuItem()
    let loginItem = NSMenuItem()
    var refreshTimer: Timer?
    var notifyLogOffset: UInt64 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Duplicate-launch guard: if another instance of this app is
        // already running, step aside instead of producing a second icon.
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        loadNotifyOffset()

        let menu = NSMenu()

        let updateLayoutItem = NSMenuItem(title: "Update Saved Layout", action: #selector(updateSavedLayout), keyEquivalent: "")
        updateLayoutItem.target = self
        menu.addItem(updateLayoutItem)

        let restoreNowItem = NSMenuItem(title: "Restore Layout Now", action: #selector(restoreLayoutNow), keyEquivalent: "")
        restoreNowItem.target = self
        menu.addItem(restoreNowItem)

        menu.addItem(NSMenuItem.separator())

        toggleItem.action = #selector(toggleWatchdog)
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        loginItem.title = "Launch at Login"
        loginItem.action = #selector(toggleLaunchAtLogin)
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        refreshState()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshState()
            self?.checkForNewLogEvents()
        }
    }

    func refreshState() {
        let running = isWatchdogRunning()
        statusItem.button?.image = makeWatchdogIcon(active: running)
        statusItem.button?.toolTip = running ? "Display Watchdog: On" : "Display Watchdog: Off"
        toggleItem.title = running ? "Turn Off Display Watchdog" : "Turn On Display Watchdog"

        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - Restore notifications

    func loadNotifyOffset() {
        if let saved = try? String(contentsOfFile: notifyOffsetStatePath, encoding: .utf8),
           let value = UInt64(saved.trimmingCharacters(in: .whitespacesAndNewlines)) {
            notifyLogOffset = value
        } else {
            // First run: start watching from the end of the existing log
            // rather than firing notifications for its entire history.
            notifyLogOffset = currentLogSize()
            saveNotifyOffset()
        }
    }

    func saveNotifyOffset() {
        try? String(notifyLogOffset).write(toFile: notifyOffsetStatePath, atomically: true, encoding: .utf8)
    }

    func currentLogSize() -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: watchdogLogPath)[.size] as? UInt64) ?? 0
    }

    func checkForNewLogEvents() {
        let size = currentLogSize()
        guard size > 0 else { return }

        // Log was rotated/truncated since we last checked; start fresh.
        if size < notifyLogOffset {
            notifyLogOffset = 0
        }
        guard size > notifyLogOffset else { return }

        guard let handle = FileHandle(forReadingAtPath: watchdogLogPath) else { return }
        defer { handle.closeFile() }
        handle.seek(toFileOffset: notifyLogOffset)
        let newData = handle.readDataToEndOfFile()
        notifyLogOffset = size
        saveNotifyOffset()

        guard let text = String(data: newData, encoding: .utf8) else { return }
        for line in text.components(separatedBy: "\n") {
            if line.contains("Display configuration restored.") {
                postNotification(title: "Display Watchdog", body: "Your display arrangement changed and was restored.")
            } else if line.contains("Restore command failed.") {
                postNotification(title: "Display Watchdog", body: "A display change was detected, but restoring the layout failed.")
            }
        }
    }

    func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Actions

    @objc func toggleWatchdog() {
        if isWatchdogRunning() {
            disableWatchdog()
        } else {
            if resolveDisplayplacer() == nil {
                let alert = NSAlert()
                alert.icon = watchdogNotifyIcon
                alert.messageText = "displayplacer Not Found"
                alert.informativeText = "The display watchdog depends on displayplacer, which isn't installed.\n\nInstall it with:\nbrew install displayplacer\n\nthen try turning the watchdog on again."
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
            enableWatchdog()
        }
        // Give launchd a moment to update state before refreshing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshState()
        }
    }

    @objc func updateSavedLayout() {
        guard let currentCount = countCurrentDisplays() else {
            let alert = NSAlert()
            alert.icon = watchdogNotifyIcon
            alert.messageText = "Couldn't Detect Displays"
            alert.informativeText = "displayplacer isn't installed, or its output couldn't be read. Install it with:\nbrew install displayplacer"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let previousCount = countSavedDisplays()
        let alert = NSAlert()
        alert.icon = watchdogNotifyIcon

        if let previousCount, currentCount < previousCount {
            alert.messageText = "Fewer Displays Than Before"
            alert.informativeText = "Only \(currentCount) display(s) detected, but \(previousCount) were previously saved — this usually means one is disconnected.\n\nSave this as the new protected layout anyway?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Save Anyway")
        } else {
            alert.messageText = "Update Saved Layout"
            alert.informativeText = "This will protect the current arrangement of \(currentCount) display(s) going forward."
            alert.addButton(withTitle: "Save Layout")
            alert.addButton(withTitle: "Cancel")
        }

        let response = alert.runModal()
        let confirmed = (previousCount != nil && currentCount < previousCount!)
            ? response == .alertSecondButtonReturn
            : response == .alertFirstButtonReturn
        guard confirmed else { return }

        let result = runBundledScript("save-display-config")
        let resultAlert = NSAlert()
        resultAlert.icon = watchdogNotifyIcon
        if result.status == 0 {
            resultAlert.messageText = "Layout Saved"
            resultAlert.informativeText = "The current display arrangement is now the protected layout."
        } else {
            resultAlert.messageText = "Couldn't Save Layout"
            resultAlert.informativeText = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            resultAlert.alertStyle = .warning
        }
        resultAlert.runModal()
    }

    @objc func restoreLayoutNow() {
        let result = runBundledScript("restore-display-config")
        let alert = NSAlert()
        alert.icon = watchdogNotifyIcon
        if result.status == 0 {
            alert.messageText = "Layout Restored"
            alert.informativeText = "The saved display arrangement has been applied."
        } else {
            alert.messageText = "Couldn't Restore Layout"
            alert.informativeText = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            alert.alertStyle = .warning
        }
        alert.runModal()
    }

    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.icon = watchdogNotifyIcon
            alert.messageText = "Couldn't update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshState()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
