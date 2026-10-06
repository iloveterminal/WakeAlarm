import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

enum AlarmState: Equatable {
    case idle
    case armed(Date)
    /// Visual alarm active; sound may have already auto-stopped after 15 minutes.
    case ringing(started: Date)
}

@MainActor
final class AlarmController: ObservableObject {
    private static let volumeDefaultsKey = "wakeAlarm.volume"
    private static let maxBeepDuration: TimeInterval = 15 * 60

    @Published private(set) var state: AlarmState = .idle
    /// Time-of-day for today's alarm (date component is always today when set).
    @Published var alarmDate: Date
    @Published private(set) var now: Date = Date()
    /// True while the digital beep is actively playing.
    @Published private(set) var isBeeping = false
    /// 0...1 — how loud the beep gets after the ramp. Persisted across launches.
    @Published var volume: Double = 0.85 {
        didSet {
            let clamped = min(1, max(0.1, volume))
            if clamped != volume {
                volume = clamped
                return
            }
            beepPlayer.userVolume = Float(volume)
            UserDefaults.standard.set(volume, forKey: Self.volumeDefaultsKey)
        }
    }

    private let beepPlayer = DigitalBeepPlayer()
    private var sleepAssertionID: IOPMAssertionID = 0
    private var hasSleepAssertion = false
    private var lastAttentionRequest: Date = .distantPast

    init() {
        alarmDate = AlarmController.defaultAlarmDate()
        let saved = UserDefaults.standard.object(forKey: Self.volumeDefaultsKey) as? Double ?? 0.85
        volume = min(1, max(0.1, saved))
        beepPlayer.userVolume = Float(volume)
        beepPlayer.rampDuration = 30
        startClock()
    }

    var statusText: String {
        switch state {
        case .idle:
            return "No alarm set"
        case .armed(let date):
            let remaining = date.timeIntervalSince(now)
            let minutes = max(0, Int(ceil(remaining / 60.0)))
            let timePart = Self.formatTimeOnly(date)
            if minutes <= 0 {
                return "Alarm set for \(timePart)"
            }
            if minutes == 1 {
                return "Alarm set for \(timePart) · in 1 min"
            }
            return "Alarm set for \(timePart) · in \(minutes) min"
        case .ringing:
            return ""
        }
    }

    var isRinging: Bool {
        if case .ringing = state { return true }
        return false
    }

    var isArmed: Bool {
        if case .armed = state { return true }
        return false
    }

    /// Target fire time if Set were pressed now (today + picked clock time).
    var todayTarget: Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: alarmDate)
        return calendar.date(
            bySettingHour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            second: 0,
            of: Date()
        ) ?? alarmDate
    }

    var canSet: Bool {
        if case .ringing = state { return false }
        if case .armed = state { return false }
        return todayTarget > Date().addingTimeInterval(5)
    }

    func setAlarm() {
        guard canSet else { return }
        let target = todayTarget
        alarmDate = target
        state = .armed(target)
        acquireSleepAssertion()
        bringWindowForward()
    }

    func cancelAlarm() {
        beepPlayer.stop()
        isBeeping = false
        releaseSleepAssertion()
        state = .idle
    }

    func stopAlarm() {
        beepPlayer.stop()
        isBeeping = false
        releaseSleepAssertion()
        state = .idle
    }

    // MARK: - Internals

    private func startClock() {
        Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                self.tick()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func tick() {
        now = Date()

        switch state {
        case .armed(let target):
            if now >= target {
                fireAlarm()
            }
        case .ringing(let started):
            nudgeDockBounceIfNeeded()
            if isBeeping, now.timeIntervalSince(started) >= Self.maxBeepDuration {
                beepPlayer.stop()
                isBeeping = false
            }
        case .idle:
            break
        }
    }

    private func fireAlarm() {
        let started = Date()
        state = .ringing(started: started)
        isBeeping = true
        beepPlayer.userVolume = Float(volume)
        beepPlayer.start()
        // Show the window but don't steal focus — that lets the Dock keep bouncing
        // until you click the app (macOS only bounces for inactive apps).
        for window in NSApp.windows {
            window.orderFrontRegardless()
        }
        NSSound.beep()
        NSApp.requestUserAttention(.criticalRequest)
        lastAttentionRequest = Date()
    }

    /// Keep bouncing the Dock icon while ringing if the app isn't frontmost.
    private func nudgeDockBounceIfNeeded() {
        guard !NSApp.isActive else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAttentionRequest) >= 2.0 else { return }
        NSApp.requestUserAttention(.criticalRequest)
        lastAttentionRequest = now
    }

    private func bringWindowForward() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func acquireSleepAssertion() {
        releaseSleepAssertion()
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "WakeAlarm armed" as CFString,
            &assertionID
        )
        if result == kIOReturnSuccess {
            sleepAssertionID = assertionID
            hasSleepAssertion = true
        }
    }

    private func releaseSleepAssertion() {
        guard hasSleepAssertion else { return }
        IOPMAssertionRelease(sleepAssertionID)
        hasSleepAssertion = false
        sleepAssertionID = 0
    }

    /// Top of the next hour (e.g. 6:41 → 7:00). If that would be tomorrow, fall back to 9:00 today.
    private static func defaultAlarmDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        if let plusOneHour = calendar.date(byAdding: .hour, value: 1, to: now) {
            var comps = calendar.dateComponents([.year, .month, .day, .hour], from: plusOneHour)
            comps.minute = 0
            comps.second = 0
            if let candidate = calendar.date(from: comps),
               calendar.isDate(candidate, inSameDayAs: now) {
                return candidate
            }
        }
        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: now
        ) ?? now
    }

    static func formatTimeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Digits + colon only — for 7-segment / DSEG display.
    static func formatDigitalTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }

    static func formatMeridiem(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }

    static func formatWeekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}
