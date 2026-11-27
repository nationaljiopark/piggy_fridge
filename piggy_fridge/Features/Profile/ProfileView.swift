import Foundation
import Charts
import SwiftUI
import UIKit

/// "My Piggy" tab: monthly summary, eaten vs thrown chart, then one flat menu.
/// No accounts for now: everything is stored on this iPhone only.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    private let month = Date.now

    var body: some View {
        let summary = store.summary(for: month)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Small grey month label instead of a second big heading under "My Piggy".
                Text(PFDate.make("MMMM yyyy").string(from: month))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, 20)

                // Tap a tile (or the chart) to open the Summary detail for that number.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    NavigationLink { SummaryView(metric: .items) } label: {
                        StatTile(title: "Item saved", value: "\(summary.savedCount)", unit: nil)
                    }
                    NavigationLink { SummaryView(metric: .value) } label: {
                        StatTile(title: "Est. value saved", value: String(format: "£%.2f", summary.valueSaved), unit: nil)
                    }
                    NavigationLink { SummaryView(metric: .food) } label: {
                        StatTile(title: "Est. food saved", value: String(format: "%.1f", summary.weightSaved), unit: "kg")
                    }
                    NavigationLink { SummaryView(metric: .co2e) } label: {
                        StatTile(title: "Est. CO2e impact", value: String(format: "%.1f", summary.co2Saved), unit: "kg")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                NavigationLink { SummaryView(metric: .items) } label: {
                    WeeklyChartCard(stats: store.weeklyStats(for: month))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                settings

                Text("Piggy Fridge \(Self.appVersion)")
                    .font(.caption)
                    .foregroundStyle(Palette.chartGray)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                #if DEBUG
                developer
                #endif
            }
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Palette.ink)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { PFTabHeader(title: "My Piggy") { EmptyView() } }
        .safeAreaInset(edge: .bottom, spacing: 0) { PFTabBar() }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: Menu (one flat list, no section headers)

    private var settings: some View {
        VStack(spacing: 0) {
            NavigationLink(value: ProfileRoute.notificationSettings) {
                SettingsRow(symbol: "bell.fill", title: "Notifications")
            }
            NavigationLink(value: ProfileRoute.history) {
                SettingsRow(symbol: "clock.fill", title: "History")
            }
            NavigationLink { MyDataView() } label: {
                SettingsRow(symbol: "person.fill", title: "Profile")
            }
            Button {
                if let url = Feedback.mailURL { openURL(url) }
            } label: {
                SettingsRow(symbol: "questionmark.circle.fill", title: "Help & Feedback")
            }
            NavigationLink(value: ProfileRoute.privacy) {
                SettingsRow(symbol: "hand.raised.fill", title: "Privacy Policy")
            }
            NavigationLink(value: ProfileRoute.terms) {
                SettingsRow(symbol: "doc.text.fill", title: "Terms of Use")
            }
        }
        .buttonStyle(.plain)
    }

    #if DEBUG
    private var developer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Developer (Debug builds only)").font(.footnote.weight(.semibold)).foregroundStyle(Palette.inkTertiary)
            HStack(spacing: 10) {
                Button("Load sample data") { store.loadSampleData() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Start empty") { store.clearAll() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
    #endif
}

/// My > Profile: your first name, a copy of your data, history reset, and delete everything on this iPhone.
struct MyDataView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirmDelete = false
    @State private var confirmResetHistory = false

    private var nameChanged: Bool {
        name.trimmingCharacters(in: .whitespaces) != store.userName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledField(label: "First name") {
                        TextField("First name", text: $name)
                            .textContentType(.givenName)
                            .submitLabel(.done)
                            .onSubmit(saveName)
                    }
                    if nameChanged {
                        Button("Save name", action: saveName)
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Text("Used only to greet you. It stays on this iPhone.")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    if let url = store.exportData() {
                        ShareLink(item: url) {
                            SettingsRow(symbol: "square.and.arrow.down.fill", title: "Export my data")
                        }
                    }
                    Button { confirmResetHistory = true } label: {
                        SettingsRow(symbol: "clock.arrow.circlepath", title: "Reset history", destructive: true)
                    }
                    Button { confirmDelete = true } label: {
                        SettingsRow(symbol: "trash.fill", title: "Delete all data", destructive: true)
                    }
                }
                .buttonStyle(.plain)

                Text("Your food list is stored only on this iPhone. Export it any time to keep a copy.")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 12)
        }
        .foregroundStyle(Palette.ink)
        .pfTopBar("Profile")
        .onAppear { name = store.userName }
        .alert("Reset all history?", isPresented: $confirmResetHistory) {
            Button("Reset", role: .destructive) {
                store.resetHistory()
                toasts.show("History was reset")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every eaten, frozen and thrown record will be removed. Food in My Food stays. You can’t undo this.")
        }
        .alert("Delete all your data?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                store.deleteAccount()
                toasts.show("Your data was deleted")
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your name, food list, history and reminder settings will be removed from this iPhone. You can’t undo this.")
        }
    }

    private func saveName() {
        store.setUserName(name)
        toasts.show("Name saved")
    }
}

enum Feedback {
    static let address = "noontidestudio@gmail.com"

    static var mailURL: URL? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let body = "Hi Piggy Fridge team,\n\n\n\nApp version \(version) (\(build)) · iOS \(UIDevice.current.systemVersion)\nPlease keep this line so we can help faster."
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = address
        parts.queryItems = [URLQueryItem(name: "subject", value: "Piggy Fridge feedback"),
                            URLQueryItem(name: "body", value: body)]
        return parts.url
    }
}

struct SettingsRow: View {
    let symbol: String
    let title: String
    var destructive = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(destructive ? Palette.danger : Palette.inkSecondary)   // 아이콘은 연한 색
            Text(title)
                .font(.body)
                .foregroundStyle(destructive ? Palette.danger : Palette.ink)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.chartGray)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote).foregroundStyle(Palette.ink)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.largeTitle.weight(.bold))
                if let unit { Text(unit).font(.headline) }
            }
        }
        .pfCard()
        .accessibilityElement(children: .combine)
    }
}

/// Eaten (dark grey) stacked under thrown (light grey), one bar per week,
/// faint scale lines behind the bars, this week's label in black Medium.
struct WeeklyChartCard: View {
    let stats: [AppStore.WeekStat]
    /// Bars grow in one by one when the card appears.
    @State private var revealed = 0

    private static let eatenColor = Palette.inkSecondary
    private static let thrownColor = Color(red: 213 / 255, green: 214 / 255, blue: 216 / 255)   // #D5D6D8

    /// The label of the week that contains today (weeks of 7 days from the 1st).
    private var thisWeekLabel: String? {
        let index = (Calendar.current.component(.day, from: .now) - 1) / 7
        return stats.indices.contains(index) ? stats[index].label : stats.last?.label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Eaten vs thrown, by week").font(.footnote)
            Chart {
                ForEach(Array(stats.enumerated()), id: \.element.id) { i, week in
                    let k: Double = i < revealed ? 1 : 0
                    // Two bars with the same x stack on top of each other: eaten first, thrown on top.
                    BarMark(x: .value("Week", week.label), y: .value("Items", Double(week.eaten) * k), width: .fixed(22))
                        .foregroundStyle(Self.eatenColor)
                    BarMark(x: .value("Week", week.label), y: .value("Items", Double(week.thrown) * k), width: .fixed(22))
                        .foregroundStyle(Self.thrownColor)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                    AxisValueLabel().font(.caption2).foregroundStyle(Palette.chartGray)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.caption2.weight(label == thisWeekLabel ? .medium : .regular))
                                .foregroundStyle(label == thisWeekLabel ? Palette.ink : Palette.chartGray)
                        }
                    }
                }
            }
            .chartYScale(domain: 0...max(1, Double(stats.map { $0.eaten + $0.thrown }.max() ?? 1)))
            .chartLegend(.hidden)
            .frame(height: 130)
            .task {
                revealed = 0
                try? await Task.sleep(for: .milliseconds(200))
                for i in 1...max(stats.count, 1) {
                    withAnimation(.easeOut(duration: 0.45)) { revealed = i }
                    try? await Task.sleep(for: .milliseconds(130))
                }
            }
            HStack(spacing: 14) {
                legend(Self.eatenColor, "Eaten")
                legend(Self.thrownColor, "Thrown")
            }
            .font(.caption)
            .foregroundStyle(Palette.inkSecondary)
        }
        .pfCard()
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }
}
