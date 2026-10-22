import AppKit
import CoreGraphics
import Foundation
import os

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray?
@_silgen_name("CGSGetSymbolicHotKeyValue")
private func CGSGetSymbolicHotKeyValue(
    _ hotKey: Int32,
    _ keyEquivalent: UnsafeMutablePointer<UInt16>,
    _ keyCode: UnsafeMutablePointer<UInt16>,
    _ modifiers: UnsafeMutablePointer<UInt32>
) -> Int32
@_silgen_name("CGSIsSymbolicHotKeyEnabled")
private func CGSIsSymbolicHotKeyEnabled(_ hotKey: Int32) -> Bool

/// After an external display sleeps and comes back, the Dock can stop acting on
/// "Switch to Desktop N" for some desktops (seen: only the first two worked) while
/// the shortcuts still look registered. Restarting the Dock fixes it. So when a rule
/// sends one of those shortcuts and no desktop changes, this restarts the Dock and
/// sends the shortcut again. Nothing happens while switching works.
@MainActor
final class DesktopSwitchWatchdog {
    struct Snapshot: Equatable {
        /// Desktops (not full-screen spaces) in Mission Control order, across displays.
        var desktops: [Int]
        /// The current space of each display.
        var current: Set<Int>
    }

    enum Verdict: Equatable {
        case switched
        case stuck
    }

    /// Symbolic hot keys "Switch to Desktop 1" ... "Switch to Desktop 16".
    private static let hotKeys: ClosedRange<Int32> = 118...133
    private static let modifierBits: UInt32 = 0x1E0000 // shift, control, option, command
    private static let checkDelay: TimeInterval = 0.6
    private static let minRepairInterval: TimeInterval = 60
    private static let dockBundleID = "com.apple.dock"

    private let isEnabled: () -> Bool
    private let resend: (UInt16, CGEventFlags) -> Void
    private var pendingCheck: DispatchWorkItem?
    private var lastRepair: Date?
    private let log = Logger(subsystem: "dev.tahaelghabi.BetterModifiers", category: "desktops")

    init(isEnabled: @escaping () -> Bool, resend: @escaping (UInt16, CGEventFlags) -> Void) {
        self.isEnabled = isEnabled
        self.resend = resend
    }

    /// Call after posting a key. Ignores anything that isn't an enabled Switch to Desktop shortcut.
    func didSend(keyCode: UInt16, flags: CGEventFlags) {
        guard flags.rawValue & UInt64(Self.modifierBits) != 0, isEnabled(),
              let number = Self.desktopNumber(keyCode: keyCode, flags: flags),
              let before = Self.snapshot(), number <= before.desktops.count else { return }
        let target = before.desktops[number - 1]
        // Already on that desktop: nothing is supposed to change.
        guard !before.current.contains(target) else { return }
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.check(number: number, target: target, before: before, keyCode: keyCode, flags: flags)
            }
        }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.checkDelay, execute: work)
    }

    /// Any change of a current space counts as a switch, so a desktop numbering that
    /// differs from the Dock's never restarts it.
    nonisolated static func verdict(before: Snapshot, after: Snapshot, target: Int) -> Verdict {
        if after.current.contains(target) || after.current != before.current { return .switched }
        return .stuck
    }

    private func check(number: Int, target: Int, before: Snapshot, keyCode: UInt16, flags: CGEventFlags) {
        pendingCheck = nil
        guard let after = Self.snapshot(), Self.verdict(before: before, after: after, target: target) == .stuck else {
            return
        }
        if let lastRepair, Date().timeIntervalSince(lastRepair) < Self.minRepairInterval {
            log.notice("Desktop \(number) didn't switch; Dock restarted \(Int(Date().timeIntervalSince(lastRepair)))s ago, not again")
            return
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleID).first else {
            return
        }
        lastRepair = Date()
        let oldPID = dock.processIdentifier
        NSLog("[BetterModifiers] Switch to Desktop %d did nothing; restarting the Dock", number)
        kill(oldPID, SIGTERM)
        waitForDock(replacing: oldPID, attempts: 24) { [weak self] in
            self?.resend(keyCode, flags)
        }
    }

    /// launchd relaunches the Dock; once it's up, give it a moment to register the shortcuts.
    private func waitForDock(replacing oldPID: pid_t, attempts: Int, then action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let dock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleID)
                    .first { $0.processIdentifier != oldPID && $0.isFinishedLaunching }
                if dock != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { MainActor.assumeIsolated { action() } }
                } else if attempts > 0 {
                    self.waitForDock(replacing: oldPID, attempts: attempts - 1, then: action)
                } else {
                    self.log.error("Dock didn't come back after the restart")
                }
            }
        }
    }

    static func desktopNumber(keyCode: UInt16, flags: CGEventFlags) -> Int? {
        let mods = UInt32(truncatingIfNeeded: flags.rawValue) & modifierBits
        for hotKey in hotKeys {
            var equivalent: UInt16 = 0, code: UInt16 = 0, hotKeyMods: UInt32 = 0
            guard CGSGetSymbolicHotKeyValue(hotKey, &equivalent, &code, &hotKeyMods) == 0 else { continue }
            if code == keyCode, hotKeyMods & modifierBits == mods, CGSIsSymbolicHotKeyEnabled(hotKey) {
                return Int(hotKey - hotKeys.lowerBound) + 1
            }
        }
        return nil
    }

    static func snapshot() -> Snapshot? {
        guard let displays = CGSCopyManagedDisplaySpaces(_CGSDefaultConnection()) as? [NSDictionary] else { return nil }
        var snapshot = Snapshot(desktops: [], current: [])
        for display in displays {
            if let id = (display["Current Space"] as? NSDictionary)?["ManagedSpaceID"] as? Int {
                snapshot.current.insert(id)
            }
            for space in display["Spaces"] as? [NSDictionary] ?? [] where space["type"] as? Int == 0 {
                if let id = space["ManagedSpaceID"] as? Int { snapshot.desktops.append(id) }
            }
        }
        return snapshot.desktops.isEmpty ? nil : snapshot
    }
}
