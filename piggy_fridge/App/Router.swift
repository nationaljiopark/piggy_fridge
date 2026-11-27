import Foundation
import Observation
import SwiftUI
import UIKit

enum AppTab: Hashable {
    case home
    case my
}

enum HomeRoute: Hashable {
    case item(UUID)
    case inbox
    case notificationSettings
}

enum ProfileRoute: Hashable {
    case signIn
    case signUp
    case signUpEmail
    case accountReady
    case resetLinkSent(String)
    case account
    case editName
    case changePassword
    case deleteAccount
    case accountDeleted
    case history
    case record(UUID)
    case notificationSettings
    case item(UUID)
    case privacy
    case terms
}

/// App-wide navigation state: selected tab, stacks and full-screen flows.
@Observable
final class Router {
    /// Shared so a tap on a notification can open the right food.
    static let shared = Router()
    var tab: AppTab = .home
    var homePath: [HomeRoute] = []
    /// Which Home view is showing. Tapping Home again goes back to the list.
    var homeMode: HomeMode = .list
    var homeStorage: StorageFilter = .all
    /// True once the pig splash has finished (the fridge animation waits for it).
    var splashDone = false
    var profilePath: [ProfileRoute] = []
    var showScan = false
    var showSearch = false
    var addFood: AddFoodDraft?
    var showReminderPrompt = false
    var showOnboarding = false

    func startAddFood(_ draft: AddFoodDraft = AddFoodDraft()) {
        addFood = draft
    }

    func goHome() {
        profilePath = []
                homePath = []
                tab = .home
                showOnboarding = false
    }
}

/// Dark pill toast at the bottom of the screen, with optional action (Undo, View...).
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let actionTitle: String?
    }

    private(set) var current: Toast?
    @ObservationIgnored private var action: (() -> Void)?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ message: String, actionTitle: String? = nil, duration: Double = 2.5, action: (() -> Void)? = nil) {
        dismissTask?.cancel()
        self.action = action
        withAnimation(.snappy(duration: 0.3)) {
            current = Toast(message: message, actionTitle: actionTitle)
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func performAction() {
        let run = action
        dismiss()
        run?()
    }

    func dismiss() {
        dismissTask?.cancel()
        action = nil
        withAnimation(.snappy(duration: 0.3)) {
            current = nil
        }
    }
}
