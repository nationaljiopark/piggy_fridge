import Foundation
import SwiftUI
import UIKit

/// Asked once, after the first food is saved (Figma "Reminder prompt").
/// Tap the time box to open it and change the time and how early Use By reminders come.
/// Changes are only saved when "Turn on reminders" is tapped; "Not now" keeps the old settings.
struct ReminderPromptSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ReminderSettings()   // working copy, filled from the store on appear
    @State private var editing = false              // is the time box open?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "bell.fill")
                    .font(.title)
                    .foregroundStyle(Palette.ink)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Palette.yellow))
                    .padding(.top, 28)

                VStack(spacing: 6) {
                    Text("Want expiry reminders?").font(.title2.weight(.bold))
                    Text("Get notified before your food expires.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }

                reminderBox

                Button("Turn on reminders") { Task { await turnOn() } }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Not now") { notNow() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .onAppear { draft = store.reminders }
        // The sheet grows when the box opens and shrinks back when it closes.
        .presentationDetents([.height(editing ? 580 : 380)])
        .interactiveDismissDisabled()
    }

    // MARK: Time box (tap to edit)

    private var reminderBox: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { editing.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock")
                    Text(draft.timeLabel).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(draft.whenLabel).font(.footnote).foregroundStyle(Palette.inkSecondary)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.chartGray)
                        .rotationEffect(.degrees(editing ? 180 : 0))
                }
                .foregroundStyle(Palette.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(editing ? "Closes the reminder options" : "Change the reminder time and days")

            if editing {
                Divider().padding(.vertical, 12)

                DatePicker("Reminder time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 150)
                    .clipped()

                Divider().padding(.vertical, 8)

                // Use By food: how early the first reminder comes (one more on the day itself)
                HStack {
                    Text("Use By food").font(.subheadline)
                    Spacer()
                    EarlyReminderMenu(selection: daysBinding)
                }
                .frame(minHeight: 44)

                Text("Plus one on the expiry day. Best Before food gets one reminder on the day. Change this any time in My → Notifications.")
                    .font(.caption)
                    .foregroundStyle(Palette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
        .tint(Palette.ink)
        .pfCard(padding: 14)
    }

    /// The wheel works with a Date; we only keep its hour and minute.
    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: draft.hour, minute: draft.minute, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            draft.hour = parts.hour ?? draft.hour
            draft.minute = parts.minute ?? draft.minute
        }
    }

    /// 0 = no early reminder; 1–3 = days before the Use By date.
    private var daysBinding: Binding<Int> {
        Binding {
            draft.dayBefore ? draft.daysBefore : 0
        } set: { days in
            draft.dayBefore = days > 0
            if days > 0 { draft.daysBefore = days }
        }
    }

    // MARK: Actions

    /// Turn on reminders:
    /// - first time: iOS shows its own "Allow notifications" pop-up
    /// - already allowed: reminders switch on straight away
    /// - previously denied: iOS never asks twice, so we open the iPhone's notification settings for this app
    private func turnOn() async {
        store.hasAskedReminders = true
        let status = await ReminderScheduler.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            enable()
        case .notDetermined:
            let granted = await ReminderScheduler.requestAuthorization()
            if granted {
                enable()
            } else {
                var settings = draft            // keep the time they picked, but switched off
                settings.enabled = false
                store.updateReminders(settings)
                dismiss()
                toasts.show("Notifications are off on this phone.", actionTitle: "Settings", duration: 4) {
                    ReminderScheduler.enableAfterSettings = true
                    ReminderScheduler.openSystemSettings()
                }
            }
        default:
            store.updateReminders(draft)        // so the chosen time is used once they allow it in Settings
            ReminderScheduler.enableAfterSettings = true
            dismiss()
            ReminderScheduler.openSystemSettings()
        }
    }

    private func enable() {
        var settings = draft
        settings.enabled = true
        store.updateReminders(settings)
        dismiss()
        toasts.show("Reminders on · \(settings.timeLabel)", actionTitle: "Edit") {
            router.homePath.append(.notificationSettings)
        }
    }

    private func notNow() {
        store.hasAskedReminders = true
        store.changed()
        dismiss()
        toasts.show("You can turn on reminders later in My → Notifications.", duration: 3.5)
    }
}
