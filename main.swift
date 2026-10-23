// keepingawake — menu bar toggle that keeps the Mac awake, even with the lid closed.
import AppKit
import IOKit.pwr_mgt
import ServiceManagement

// MARK: - Sleep control

/// Idle sleep (display + system) via IOKit power assertions; no privileges needed.
final class IdleSleepBlocker {
    private var ids: [IOPMAssertionID] = []

    func enable() {
        guard ids.isEmpty else { return }
        for type in [kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep] {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "keepingawake" as CFString, &id) == kIOReturnSuccess {
                ids.append(id)
            }
        }
    }

    func disable() {
        ids.forEach { IOPMAssertionRelease($0) }
        ids.removeAll()
    }
}

/// Lid-close sleep via `pmset disablesleep`, which needs root.
/// Runs through `sudo -n`, allowed without a password by /etc/sudoers.d/keepingawake (`make sudoers`).
enum LidSleep {
    @discardableResult
    static func setDisabled(_ disabled: Bool) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    enum InstallResult { case installed, cancelled, failed(String) }

    /// One-time setup: installs the sudoers rule behind the system admin password dialog.
    static func installSudoersRule() -> InstallResult {
        let rule = "\(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        let shell = """
            f=$(mktemp) && printf '%s\\n' '\(rule)' > "$f" && /usr/sbin/visudo -cf "$f" >/dev/null \
            && /usr/bin/install -m 0440 -o root -g wheel "$f" /etc/sudoers.d/keepingawake; rc=$?; rm -f "$f"; exit $rc
            """
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with prompt \"keepingawake wants to allow disabling sleep with the lid closed.\" with administrator privileges"

        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return .installed }
        if error[NSAppleScript.errorNumber] as? Int == -128 { return .cancelled }
        return .failed(error[NSAppleScript.errorMessage] as? String ?? "\(error)")
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let idle = IdleSleepBlocker()
    private var signalSources: [DispatchSourceSignal] = []
    private var active = false

    private lazy var activeIcon = icon("Active")
    private lazy var inactiveIcon = icon("Inactive")

    func applicationDidFinishLaunching(_ note: Notification) {
        // A previous crash could have left lid sleep disabled.
        LidSleep.setDisabled(false)
        handleTerminationSignals()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        render()
    }

    func applicationWillTerminate(_ note: Notification) {
        if active { setActive(false) }
    }

    // pkill / logout must restore sleep too, not just Quit.
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            setActive(!active)
        }
    }

    private func setActive(_ on: Bool) {
        active = on
        if on {
            idle.enable()
            if !LidSleep.setDisabled(true) { setUpLidSleep() }
        } else {
            idle.disable()
            LidSleep.setDisabled(false)
        }
        render()
    }

    private func render() {
        statusItem.button?.image = active ? activeIcon : inactiveIcon
        statusItem.button?.toolTip = active
            ? "keepingawake: sleep disabled (lid closed too)"
            : "keepingawake: off"
    }

    private func showMenu() {
        let menu = NSMenu()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Attach only for this click so a left click keeps toggling.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            alert("Could not change Launch at Login", error.localizedDescription)
        }
    }

    // First activation without the sudoers rule: ask for the admin password once, then retry.
    private func setUpLidSleep() {
        NSApp.activate()
        switch LidSleep.installSudoersRule() {
        case .installed:
            if !LidSleep.setDisabled(true) {
                alert("Lid-closed sleep is still enabled", "The sudo rule is installed, but pmset failed.")
            }
        case .cancelled:
            break  // stays in idle-only mode; next activation asks again
        case .failed(let message):
            alert("Could not install the sudo rule",
                  message + "\n\nThe display stays on, but the Mac will sleep when the lid is closed.")
        }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    private func icon(_ name: String) -> NSImage? {
        let img = Bundle.main.image(forResource: name)
        img?.isTemplate = true
        return img
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
