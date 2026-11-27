import Foundation
import SwiftUI
import UIKit

@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore.shared
    @State private var router = Router.shared
    @State private var toasts = ToastCenter()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
                .environment(toasts)
                .tint(Palette.buttonDark)
                .preferredColorScheme(.light)
                .overlay {
                    if showSplash {
                        PixelPSplashView { withAnimation(.easeIn(duration: 0.3)) { showSplash = false; router.splashDone = true } }
                            .transition(.opacity)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await store.collectDeliveredReminders() }
                        ReminderScheduler.reschedule(items: store.items, settings: store.reminders)
                    }
                    guard phase == .active, ReminderScheduler.enableAfterSettings else { return }
                    Task {
                        let status = await ReminderScheduler.authorizationStatus()
                        guard status == .authorized || status == .provisional else { return }
                        ReminderScheduler.enableAfterSettings = false
                        var settings = store.reminders
                        settings.enabled = true
                        store.updateReminders(settings)
                        toasts.show("Reminders on · \(settings.timeLabel)")
                    }
                }
        }
    }
}
