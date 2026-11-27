import Foundation
import SwiftUI
import UIKit

/// Two tabs (Home, My) with the yellow + button in the middle, as in the Figma bottom nav.
struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        @Bindable var router = router

        ZStack {
            switch router.tab {
            case .home:
                NavigationStack(path: $router.homePath) {
                    MyFoodView()
                        .navigationDestination(for: HomeRoute.self) { route in
                            switch route {
                            case .item(let id): ItemDetailView(itemID: id)
                            case .inbox: InboxView()
                            case .notificationSettings: NotificationSettingsView()
                            }
                        }
                }
            case .my:
                NavigationStack(path: $router.profilePath) {
                    ProfileView()
                        .navigationDestination(for: ProfileRoute.self) { route in
                            ProfileDestination(route: route)
                        }
                }
            }
        }
        .overlay { ToastHost() }
        .fullScreenCover(isPresented: $router.showScan) {
            ScanFlowView()
                .environment(store).environment(router).environment(toasts)
        }
        .fullScreenCover(item: $router.addFood) { draft in
            AddFoodView(draft: draft)
                .environment(store).environment(router).environment(toasts)
        }
        .fullScreenCover(isPresented: $router.showSearch) {
            SearchView()
                .environment(store).environment(router).environment(toasts)
        }
        .sheet(isPresented: $router.showReminderPrompt) {
            ReminderPromptSheet()
                .environment(store).environment(router).environment(toasts)
                .presentationCornerRadius(24)
        }
    }
}

/// Custom bottom bar: Home, + (opens scan), My.
struct PFTabBar: View {
    @Environment(Router.self) private var router

    var body: some View {
        HStack(alignment: .center) {
            tabButton(.home, title: "Home", symbol: "house.fill")
            Spacer()
            Button {
                router.showScan = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Palette.yellow))
            }
            .accessibilityLabel("Add food")
            Spacer()
            tabButton(.my, title: "My", symbol: "person.fill")
        }
        .padding(.horizontal, 56)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background {
            // Fill all the way down behind the home indicator so list rows never show under the bar.
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.04), radius: 8, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabButton(_ tab: AppTab, title: String, symbol: String) -> some View {
        let selected = router.tab == tab
        return Button {
            if tab == .home {
                router.homePath = []
                router.homeMode = .list     // Calendar -> tap Home -> back to the list
            } else if router.tab == tab {
                router.profilePath = []
            }
            router.tab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2.weight(.medium))
            }
            .foregroundStyle(selected ? Palette.ink : Palette.chartGray)
            .frame(width: 56)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
