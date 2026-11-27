import Foundation
import SwiftUI
import UIKit

enum HomeMode: String, CaseIterable, Identifiable {
    case list = "List"
    case calendar = "Calendar"
    var id: String { rawValue }
}

/// Home tab: "My Food" with List / Calendar, or the first-time welcome when empty.
struct MyFoodView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if store.items.isEmpty {
                    FirstTimeHomeContent()
                } else {
                    HomeModeControl(mode: Binding(get: { router.homeMode }, set: { router.homeMode = $0 }))
                        .padding(.horizontal, 20)

                    if router.homeMode == .list {
                        StorageTabs(filter: Binding(get: { router.homeStorage }, set: { router.homeStorage = $0 }))
                            .transition(.move(edge: .leading))
                    }

                    // List and Calendar slide sideways (ease in). Nothing scales or cross-fades.
                    ZStack(alignment: .top) {
                        if router.homeMode == .list {
                            FoodListContent()
                                .transition(.move(edge: .leading))
                        } else {
                            FoodCalendarView()
                                .transition(.move(edge: .trailing))
                        }
                    }
                    .clipped()
                    .animation(.easeIn(duration: 0.3), value: router.homeMode)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 24)
            .animation(.easeIn(duration: 0.3), value: router.homeMode)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if store.items.isEmpty && !store.hasSeenCoachTip {
                    CoachTip { store.hasSeenCoachTip = true; store.changed() }
                        .padding(.bottom, 6)
                }
                PFTabBar()
            }
        }
    }

    private var header: some View {
        PFTabHeader(title: "My Food") {
            Button {
                router.showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Search")

            NavigationLink(value: HomeRoute.inbox) {
                Image(systemName: "bell.fill")
                    .font(.body)
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) {
                        if store.unreadCount > 0 {
                            Circle().fill(Palette.danger).frame(width: 8, height: 8).offset(x: -10, y: 10)
                        }
                    }
            }
            .accessibilityLabel(store.unreadCount > 0 ? "Notifications, \(store.unreadCount) new" : "Notifications")
        }
        .foregroundStyle(Palette.inkTertiary)
    }
}

/// Where the food is kept. "All" shows everything by date, with the freezer folded into one summary row.
enum StorageFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case fridge = "Fridge"
    case freezer = "Freezer"
    case cupboard = "Cupboard"
    var id: String { rawValue }

    var storage: Storage? {
        switch self {
        case .all: nil
        case .fridge: .fridge
        case .freezer: .freezer
        case .cupboard: .cupboard
        }
    }
}

/// Horizontal tabs: All / Fridge / Freezer / Cupboard, each with a count.
struct StorageTabs: View {
    @Environment(AppStore.self) private var store
    @Binding var filter: StorageFilter

    private func count(_ f: StorageFilter) -> Int {
        guard let s = f.storage else { return store.items.count }
        return store.items.filter { $0.storage == s }.count
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(StorageFilter.allCases) { f in
                    let selected = filter == f
                    Button { filter = f } label: {
                        Text("\(f.rawValue) \(count(f))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Color.white : Palette.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Capsule().fill(selected ? Palette.ink : Palette.surface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }
}

/// Sections: Don't eat (Use by passed), Need to review (Best before passed), Use today, Expiring soon, Later.
/// In "All", frozen food that is not urgent is folded into one "In the freezer" row.
struct FoodListContent: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private var filter: StorageFilter { router.homeStorage }

    private func visible(_ section: FoodSection) -> [FoodItem] {
        store.items(in: section).filter { item in
            guard let s = filter.storage else { return true }   // All really shows all, frozen food included
            return item.storage == s
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(FoodSection.allCases) { section in
                let items = visible(section)
                if !items.isEmpty {
                    SectionHeaderRow(title: section.title, count: items.count, note: section.note, alert: section == .dontEat)
                        .padding(.bottom, 4)
                    ForEach(items) { item in
                        NavigationLink(value: HomeRoute.item(item.id)) {
                            FoodCardRow(item: item).id(item.hashValue)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer().frame(height: 18)
                }
            }
            if filter != .all && visible(.dontEat).isEmpty && visible(.checkIt).isEmpty && visible(.today).isEmpty
                && visible(.soon).isEmpty && visible(.later).isEmpty {
                Text("Nothing in the \(filter.rawValue.lowercased()) yet.")
                    .font(.subheadline).foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, 20).padding(.top, 12)
            }
        }
    }
}

/// One food card: icon, name, date type badge, days left, date.
struct FoodCardRow: View {
    let item: FoodItem

    private var daysLeft: Int { PFDate.daysLeft(until: item.expiry) }
    private var overdue: Bool { daysLeft < 0 }
    /// Only a passed Use by date is shown in red. A passed Best before date is grey: usually still fine.
    private var unsafe: Bool { overdue && item.dateType == .useBy }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FoodIconView(asset: item.iconAsset)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name)
                    .font(.pfRowTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                // Both tags stay on one line; in a narrow row the Frozen tag shrinks to its icon.
                BadgeRowLayout {
                    DateTypeBadge(type: item.dateType, overdue: unsafe)
                    if item.storage == .freezer {
                        FrozenBadge()
                        FrozenBadge(compact: true).accessibilityHidden(true)
                    }
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(PFDate.relativeLabel(daysLeft: daysLeft))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(unsafe ? Palette.danger : (overdue ? Palette.inkSecondary : Palette.ink))
                Text(PFDate.longDay.string(from: item.expiry))
                    .font(.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
            .padding(.top, 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.chartGray)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1).padding(.leading, 20)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown when My Food is empty (Figma "Home — First time").
struct FirstTimeHomeContent: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.userName.isEmpty ? "Welcome" : "Welcome, \(store.userName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.inkSecondary)
                    Text("Add your first food").font(.title2.weight(.bold))
                    Text("Scan the date label and we’ll show you what to eat first.")
                        .font(.subheadline)
                }
                Button("Scan a date label") { router.showScan = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button("or type it in") { router.startAddFood() }
                    .buttonStyle(LinkButtonStyle())
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surface))

            VStack(alignment: .leading, spacing: 16) {
                Text("How it works").font(.pfSection)
                step(1, "Scan the date", "We read Use By and Best Before for you.")
                step(2, "See what’s due first", "Your food is sorted by date, soonest at the top.")
                step(3, "Get a nudge", "We remind you at \(store.reminders.timeLabel) the day before and on the day.")
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 20)
    }

    private func step(_ number: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Palette.surface))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.footnote).foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}

/// "Tap + to add food any time" tip above the tab bar.
struct CoachTip: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Tap + to add food any time")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Dismiss tip")
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.coach))
            Triangle()
                .fill(Palette.coach)
                .frame(width: 16, height: 8)
        }
        .transition(.opacity)
    }
}

nonisolated struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// List / Calendar switch. A plain sliding pill: no magnifying glass lens, no bounce, no scaling.
/// (The system segmented control in iOS 26 and later swells the pill while it moves.)
struct HomeModeControl: View {
    @Binding var mode: HomeMode

    private var index: Int { HomeMode.allCases.firstIndex(of: mode) ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let segment = geo.size.width / CGFloat(HomeMode.allCases.count)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surface)
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                    .padding(3)
                    .frame(width: segment)
                    .offset(x: segment * CGFloat(index))
                HStack(spacing: 0) {
                    ForEach(HomeMode.allCases) { item in
                        Button { mode = item } label: {
                            Text(item.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(mode == item ? .isSelected : [])
                    }
                }
            }
        }
        .frame(height: 40)
        .animation(.easeIn(duration: 0.3), value: mode)
    }
}
