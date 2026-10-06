import AppKit
import SwiftUI

private extension View {
    /// Show the macOS pointing-hand cursor while the pointer is over this view.
    func pointingHandCursor() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var controller: AlarmController

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 18) {
                HStack(alignment: .center, spacing: 20) {
                    // Current time — left (dominant), vertically centered
                    VStack(alignment: .leading, spacing: 12) {
                        Text(AlarmController.formatWeekday(controller.now))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(AlarmController.formatDigitalTime(controller.now))
                                .font(AppFonts.digital(size: 108))
                                .minimumScaleFactor(0.4)
                                .lineLimit(1)
                                .foregroundStyle(controller.isRinging ? Color.green : Color.primary)

                            Text(AlarmController.formatMeridiem(controller.now))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(controller.isRinging ? Color.green : Color.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    Divider()

                    // Alarm time — right
                    VStack(spacing: 8) {
                        Text("Alarm")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        BigTimePicker(date: $controller.alarmDate)
                            .disabled(controller.isRinging || controller.isArmed)
                            .opacity(controller.isRinging || controller.isArmed ? 0.55 : 1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxHeight: .infinity)

                // Fixed-height status slot so the action button never jumps.
                Text(controller.statusText)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                    .opacity(controller.statusText.isEmpty ? 0 : 1)

                // Fixed-size action button — same footprint for Set / Cancel / Stop.
                Button {
                    switch controller.state {
                    case .idle:
                        controller.setAlarm()
                    case .armed:
                        controller.cancelAlarm()
                    case .ringing:
                        controller.stopAlarm()
                    }
                } label: {
                    Text(actionButtonTitle)
                        .font(.system(size: 26, weight: .bold))
                        .frame(width: 240, height: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isRinging ? Color.green : Color.accentColor)
                .disabled({
                    if case .idle = controller.state { return !controller.canSet }
                    return false
                }())
                .keyboardShortcut(.defaultAction)
                .pointingHandCursor()
            }
            .padding(24)
            .padding(.bottom, 10)

            // Tiny volume control — bottom right, intentionally de-emphasized
            HStack(spacing: 4) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 9))
                Slider(value: $controller.volume, in: 0.1...1.0)
                    .controlSize(.mini)
                    .frame(width: 72)
            }
            .foregroundStyle(.tertiary)
            .opacity(0.55)
            .padding(.trailing, 10)
            .padding(.bottom, 8)
            .help("Alarm volume (remembered)")
        }
        .background(controller.isRinging ? Color.green.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
    }

    private var actionButtonTitle: String {
        switch controller.state {
        case .idle:
            return "Set Alarm"
        case .armed:
            return "Cancel"
        case .ringing:
            return "Stop Alarm"
        }
    }
}

/// Hour / minute steppers with editable typed fields, plus AM/PM.
struct BigTimePicker: View {
    @Binding var date: Date

    @State private var hourText: String = ""
    @State private var minuteText: String = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case hour, minute
    }

    private var calendar: Calendar { .current }

    private var hour12: Int {
        let h = calendar.component(.hour, from: date) % 12
        return h == 0 ? 12 : h
    }

    private var minute: Int {
        calendar.component(.minute, from: date)
    }

    private var isPM: Bool {
        calendar.component(.hour, from: date) >= 12
    }

    var body: some View {
        HStack(spacing: 10) {
            stepperColumn(
                text: $hourText,
                field: .hour,
                label: "Hour",
                width: 56,
                sanitize: Self.sanitizeHourInput
            ) {
                bumpHour(by: 1)
            } down: {
                bumpHour(by: -1)
            } commit: {
                commitHour()
            }

            Text(":")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .offset(y: -8)

            stepperColumn(
                text: $minuteText,
                field: .minute,
                label: "Min",
                width: 64,
                sanitize: Self.sanitizeMinuteInput
            ) {
                bumpMinute(by: 1)
            } down: {
                bumpMinute(by: -1)
            } commit: {
                commitMinute()
            }

            VStack(spacing: 6) {
                Button(action: { setMeridiem(pm: false) }) {
                    Text("AM")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(isPM ? Color.secondary.opacity(0.35) : Color.accentColor)
                .pointingHandCursor()

                Button(action: { setMeridiem(pm: true) }) {
                    Text("PM")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(isPM ? Color.accentColor : Color.secondary.opacity(0.35))
                .pointingHandCursor()
            }
        }
        .padding(.vertical, 2)
        .onAppear(perform: syncTextsFromDate)
        .onChange(of: date) { _ in
            if focusedField == nil {
                syncTextsFromDate()
            }
        }
    }

    private func stepperColumn(
        text: Binding<String>,
        field: Field,
        label: String,
        width: CGFloat,
        sanitize: @escaping (String) -> String,
        up: @escaping () -> Void,
        down: @escaping () -> Void,
        commit: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 3) {
            Button(action: up) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: width, height: 24)
            }
            .buttonStyle(.bordered)
            .pointingHandCursor()

            TextField("", text: text)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: width)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: field)
                .onSubmit(commit)
                .onChange(of: text.wrappedValue) { newValue in
                    let cleaned = sanitize(newValue)
                    if cleaned != newValue {
                        text.wrappedValue = cleaned
                    }
                }
                .onChange(of: focusedField) { newValue in
                    if newValue != field {
                        commit()
                    }
                }

            Button(action: down) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: width, height: 24)
            }
            .buttonStyle(.bordered)
            .pointingHandCursor()

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    /// Digits only, max 2 chars, value 1...12 (empty allowed while editing).
    private static func sanitizeHourInput(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(2))
        guard !digits.isEmpty else { return "" }
        guard let value = Int(digits) else { return "" }
        if value == 0 { return "" }
        if value <= 12 { return digits }
        // e.g. "19" / "99" → keep first digit if still a valid hour start
        let first = String(digits.prefix(1))
        if let firstValue = Int(first), (1...9).contains(firstValue) {
            return first
        }
        return ""
    }

    /// Digits only, max 2 chars, value 0...59 (empty allowed while editing).
    private static func sanitizeMinuteInput(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(2))
        guard !digits.isEmpty else { return "" }
        guard let value = Int(digits) else { return "" }
        if value <= 59 { return digits }
        // e.g. "60" / "99" → keep first digit if 0...5
        let first = String(digits.prefix(1))
        if let firstValue = Int(first), firstValue <= 5 {
            return first
        }
        return ""
    }

    private func syncTextsFromDate() {
        hourText = String(hour12)
        minuteText = String(format: "%02d", minute)
    }

    private func commitHour() {
        let digits = hourText.filter(\.isNumber)
        guard let value = Int(digits), (1...12).contains(value) else {
            syncTextsFromDate()
            return
        }
        applyHour12(value)
        hourText = String(value)
    }

    private func commitMinute() {
        let digits = minuteText.filter(\.isNumber)
        guard let value = Int(digits), (0...59).contains(value) else {
            syncTextsFromDate()
            return
        }
        applyMinute(value)
        minuteText = String(format: "%02d", value)
    }

    private func applyHour12(_ hour12Value: Int) {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var hour24 = hour12Value % 12
        if isPM { hour24 += 12 }
        comps.hour = hour24
        comps.second = 0
        if let next = calendar.date(from: comps) {
            date = next
        }
    }

    private func applyMinute(_ value: Int) {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        comps.minute = value
        comps.second = 0
        if let next = calendar.date(from: comps) {
            date = next
        }
    }

    private func bumpHour(by delta: Int) {
        focusedField = nil
        commitHour()
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let current = comps.hour ?? 0
        comps.hour = (current + delta + 24) % 24
        comps.second = 0
        if let next = calendar.date(from: comps) {
            date = next
        }
        syncTextsFromDate()
    }

    private func bumpMinute(by delta: Int) {
        focusedField = nil
        commitMinute()
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let current = comps.minute ?? 0
        var minute = current + delta
        var hour = comps.hour ?? 0
        while minute < 0 {
            minute += 60
            hour = (hour + 23) % 24
        }
        while minute >= 60 {
            minute -= 60
            hour = (hour + 1) % 24
        }
        comps.minute = minute
        comps.hour = hour
        comps.second = 0
        if let next = calendar.date(from: comps) {
            date = next
        }
        syncTextsFromDate()
    }

    private func setMeridiem(pm: Bool) {
        focusedField = nil
        commitHour()
        commitMinute()
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var hour = comps.hour ?? 0
        let currentlyPM = hour >= 12
        if pm && !currentlyPM {
            hour += 12
        } else if !pm && currentlyPM {
            hour -= 12
        }
        comps.hour = hour
        comps.second = 0
        if let next = calendar.date(from: comps) {
            date = next
        }
        syncTextsFromDate()
    }
}
