import Foundation
import SwiftUI
import UIKit
import UserNotifications

/// Figma "Notifications settings" and "Notifications settings — Device off".
struct NotificationSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.scenePhase) private var scenePhase
    @State private var deviceStatus: UNAuthorizationStatus = .notDetermined
    @State private var showTimePicker = false
    @AppStorage("reminderTimeConfirmed") private var timeConfirmed = false

    private var deviceOff: Bool { deviceStatus == .denied }

    var body: some View {
        let settings = store.reminders
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if deviceOff { deviceOffBanner }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Expiry reminders").font(.title2.weight(.bold))
                    Text("Get notified before your food expires.").font(.subheadline).foregroundStyle(Palette.inkSecondary)
                }

                HStack {
                    Text("Expiry reminders").font(.body)
                    Spacer()
                    PFToggle(isOn: Binding(
                        get: { settings.enabled },
                        set: { newValue in Task { await setEnabled(newValue) } }),
                             label: "Expiry reminders")
                }
                .pfCard()

                // Use By: a safety date, so an early reminder (off, or 1–3 days before) plus one on the day.
                group("Use By food", note: "A safety date. Eat, cook or freeze it by this day.") {
                    VStack(spacing: 0) {
                        // One row: tap the value to pick Off / 1 / 2 / 3 days before (same look as the Time row).
                        HStack {
                            Text("Before the date").font(.body)
                            Spacer()
                            EarlyReminderMenu(selection: Binding(
                                get: { settings.dayBefore ? settings.daysBefore : 0 },
                                set: { days in
                                    update {
                                        $0.dayBefore = days > 0
                                        if days > 0 { $0.daysBefore = days }
                                    }
                                }))
                        }
                        .frame(minHeight: 52)
                        Divider()
                        toggleRow("On the expiry day", isOn: settings.onTheDay) { on in update { $0.onTheDay = on } }
                    }
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
                }

                // Best Before (and "Not sure"): same two rows as Use By, quieter by default
                // (no early reminder, one on the day). People who often bin bread can turn the early one on.
                group("Best Before food", note: "A quality date. It’s usually fine after this, so one reminder on the day is often enough.") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Before the date").font(.body)
                            Spacer()
                            EarlyReminderMenu(selection: Binding(
                                get: { settings.bestBeforeDaysBefore },
                                set: { days in update { $0.bestBeforeDaysBefore = days } }))
                        }
                        .frame(minHeight: 52)
                        Divider()
                        toggleRow("On the expiry day", isOn: settings.bestBeforeOnTheDay) { on in
                            update { $0.bestBeforeOnTheDay = on }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
                }

                group("Reminder time") {
                    Button { showTimePicker = true } label: {
                        HStack {
                            Text("Time").font(.body)
                            Spacer()
                            Text(settings.timeLabel).font(.body.weight(.semibold))
                            .foregroundStyle(timeConfirmed ? Color.white : Palette.ink)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(timeConfirmed ? Palette.toggleGreen : Color.white))
                            .animation(.easeIn(duration: 0.3), value: timeConfirmed)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chartGray)
                        }
                        .pfCard()
                    }
                    .buttonStyle(.plain)
                }

                Text(deviceOff ? "Your settings are saved. Reminders start once notifications are on." : settings.summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .disabled(false)
            .padding(20)
        }
        .foregroundStyle(Palette.ink)
        .pfTopBar("Notifications")
        .task { deviceStatus = await ReminderScheduler.authorizationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { deviceStatus = await ReminderScheduler.authorizationStatus() }
            }
        }
        .sheet(isPresented: $showTimePicker) {
            ReminderTimeSheet(initial: settings.timeDate) { picked in
                update { $0.timeDate = picked }
                timeConfirmed = true
                toasts.show("Reminder time set to \(store.reminders.timeLabel)")
            }
            .presentationDetents([.height(340)])
            .presentationBackground(Color(.systemBackground))
            .presentationCornerRadius(24)
            .presentationDragIndicator(.hidden)
        }
    }

    private var deviceOffBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bell.slash.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications are currently off in your device settings.").font(.subheadline.weight(.semibold))
                    Text("Turn them on so Piggy Fridge can remind you.").font(.footnote).foregroundStyle(Palette.inkSecondary)
                }
            }
            Button("Enable notifications") { ReminderScheduler.openSystemSettings() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.yellow.opacity(0.35)))
    }

    private func group<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.pfLabel)
                if let note {
                    Text(note).font(.footnote).foregroundStyle(Palette.inkSecondary)
                }
            }
            content()
        }
    }

    /// One line with a switch on the right (same switch as "Expiry reminders" at the top).
    private func toggleRow(_ title: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title).font(.body)
            Spacer()
            PFToggle(isOn: Binding(get: { isOn }, set: set), label: title)
        }
        .frame(minHeight: 52)
    }

    private func update(_ change: (inout ReminderSettings) -> Void) {
        var s = store.reminders
        change(&s)
        store.updateReminders(s)
    }

    private func setEnabled(_ on: Bool) async {
        if on {
            let status = await ReminderScheduler.authorizationStatus()
            if status == .notDetermined {
                let granted = await ReminderScheduler.requestAuthorization()
                deviceStatus = granted ? .authorized : .denied
            }
            store.hasAskedReminders = true
        }
        update { $0.enabled = on }
    }
}

/// The value chip that opens a short menu: Off, 1 day before, 2 days before, 3 days before.
/// 0 means off. Looks like the white time chip in the Reminder time row.
struct EarlyReminderMenu: View {
    @Binding var selection: Int

    private func label(_ days: Int) -> String {
        switch days {
        case 0: "Off"
        case 1: "1 day before"
        default: "\(days) days before"
        }
    }

    var body: some View {
        Menu {
            Picker("Before the date", selection: $selection) {
                Text("Off").tag(0)
                ForEach(ReminderSettings.daysBeforeChoices, id: \.self) { days in
                    Text(label(days)).tag(days)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label(selection)).font(.body.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.chartGray)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
        }
        .accessibilityLabel("Before the date, \(label(selection))")
    }
}

/// Figma "Overlay / Sheet — Reminder time".
struct ReminderTimeSheet: View {
    @State var time: Date
    var onSet: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    init(initial: Date, onSet: @escaping (Date) -> Void) {
        _time = State(initialValue: initial)
        self.onSet = onSet
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Reminder time").font(.headline).padding(.top, 20)
            DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Set \(PFDate.time.string(from: time))") {
                    onSet(time)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 20)
        }
    }
}
