import Foundation
import SwiftUI
import UIKit

/// Root: plays the fridge animation on first launch, then shows the app.
struct ContentView: View {
    @AppStorage("hasSeenLaunchAnimation") private var hasSeenLaunchAnimation = true
    @Environment(Router.self) private var router
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            MainTabView()
            if !hasSeenLaunchAnimation && router.splashDone {
                FridgeLoadingView {
                    withAnimation(.easeOut(duration: 0.35)) { hasSeenLaunchAnimation = true }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .sheet(isPresented: Binding(
            get: { router.splashDone && !store.hasAskedName },
            set: { _ in }
        )) {
            NameSetupSheet()
                .environment(store)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
        .environment(Router())
        .environment(ToastCenter())
}
