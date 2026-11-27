import Foundation
import SwiftUI
import UIKit

/// Routes for the My tab.
struct ProfileDestination: View {
    let route: ProfileRoute

    var body: some View {
        switch route {
        case .signIn: SignInView()
        case .signUp: SignUpView()
        case .signUpEmail: SignUpEmailView()
        case .accountReady: AccountReadyView()
        case .resetLinkSent(let email): ResetLinkSentView(email: email)
        case .account: AccountView()
        case .editName: EditNameView()
        case .changePassword: ChangePasswordView()
        case .deleteAccount: DeleteAccountView()
        case .accountDeleted: AccountDeletedView()
        case .history: HistoryView()
        case .record(let id): RecordDetailView(recordID: id)
        case .notificationSettings: NotificationSettingsView()
        case .item(let id): ItemDetailView(itemID: id)
        case .privacy: PrivacyPolicyView()
        case .terms: TermsView()
        }
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case eaten = "Eaten"
    case frozen = "Frozen"
    case thrown = "Thrown away"

    var id: String { rawValue }

    func includes(_ outcome: Outcome) -> Bool {
        switch self {
        case .all: true
        case .eaten: outcome == .eaten
        case .frozen: outcome == .frozen
        case .thrown: outcome == .thrown
        }
    }
}

/// Month switcher, filter chips and the list of what was eaten, frozen or thrown away.
struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var month = PFDate.startOfMonth(.now)
    @State private var filter: HistoryFilter = .all
    @State private var showMonthPicker = false
    @State private var confirmReset = false
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        let monthRecords = store.records(inMonthOf: month)
        let records = monthRecords.filter { filter.includes($0.outcome) }
        let summary = store.summary(for: month)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                monthSwitcher(summary: summary, isEmpty: monthRecords.isEmpty)
                if !monthRecords.isEmpty {
                    filters
                }
                if records.isEmpty {
                    emptyState(monthIsEmpty: monthRecords.isEmpty)
                } else {
                    list(records)
                }
            }
            .padding(.vertical, 12)
        }
        .pfTopBar("History") {
            if !store.history.isEmpty {
                Button("Reset") { confirmReset = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.danger)
            }
        }
        .alert("Reset all history?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                store.resetHistory()
                toasts.show("History was reset")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every eaten, frozen and thrown record will be removed, and your monthly summary starts from zero. Food in My Food stays. You can’t undo this.")
        }
        .sheet(isPresented: $showMonthPicker) {
            MonthPickerSheet(month: $month)
                .presentationDetents([.height(380)])
                .presentationBackground(Color(.systemBackground))
                .presentationCornerRadius(24)
                .presentationDragIndicator(.hidden)
        }
    }

    private func monthSwitcher(summary: AppStore.MonthSummary, isEmpty: Bool) -> some View {
        let isCurrentMonth = PFDate.isSameMonth(month, .now)
        return HStack {
            roundButton("chevron.left", label: "Previous month") { month = PFDate.addingMonths(-1, to: month) }
            Spacer()
            VStack(spacing: 2) {
                Button { showMonthPicker = true } label: {
                    HStack(spacing: 4) {
                        Text(PFDate.month.string(from: month)).font(.headline)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Palette.ink)
                }
                .accessibilityLabel("Choose month")
                Text(isEmpty ? "Nothing marked" : "\(summary.savedCount) used in time · \(summary.thrownCount) thrown away")
                    .font(.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
            Spacer()
            roundButton("chevron.right", label: "Next month") { month = PFDate.addingMonths(1, to: month) }
                .disabled(isCurrentMonth)
                .opacity(isCurrentMonth ? 0.35 : 1)
        }
        .padding(.horizontal, 20)
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Palette.surface))
        }
        .accessibilityLabel(label)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases) { f in
                    Button(f.rawValue) { withAnimation(.snappy) { filter = f } }
                        .buttonStyle(ChipStyle(isSelected: filter == f))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func list(_ records: [HistoryRecord]) -> some View {
        let groups = Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.markedAt) }
        let days = groups.keys.sorted(by: >)
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(days, id: \.self) { day in
                Text(PFDate.dayHeader(for: day))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                ForEach(groups[day] ?? []) { record in
                    HistoryRow(record: record) {
                        router.startAddFood(store.draftToAddAgain(record.item))
                    }
                }
            }
        }
    }

    private func emptyState(monthIsEmpty: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Palette.surface))
            Text(monthIsEmpty ? "Nothing marked this month" : "Nothing in this filter").font(.headline)
            Text("When you mark food as eaten, frozen or thrown away, it shows up here.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 60)
    }
}

struct OutcomeTag: View {
    let outcome: Outcome

    var body: some View {
        Label(outcome.title, systemImage: outcome.symbol)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(outcome == .thrown ? Palette.dangerBackground : Palette.surface))
            .foregroundStyle(outcome == .thrown ? Palette.danger : Palette.ink)
    }
}

struct HistoryRow: View {
    let record: HistoryRecord
    var onAddAgain: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: ProfileRoute.record(record.id)) {
                HStack(spacing: 12) {
                    FoodIconView(asset: record.item.iconAsset, size: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.item.name).font(.subheadline.weight(.medium))
                        HStack(spacing: 8) {
                            OutcomeTag(outcome: record.outcome)
                            Text(PFDate.time.string(from: record.markedAt))
                                .font(.caption)
                                .foregroundStyle(Palette.inkTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onAddAgain) {
                Text("+ Add again")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

/// Figma "History — Record detail".
struct RecordDetailView: View {
    let recordID: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let record = store.history.first(where: { $0.id == recordID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FoodIconView(asset: record.item.iconAsset, size: 120, framed: false)
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surface))
                    Text(record.item.name).font(.title2.weight(.bold))
                    OutcomeTag(outcome: record.outcome)
                    VStack(spacing: 0) {
                        InfoRow(label: "Marked on", value: PFDate.weekdayDay.string(from: record.markedAt) + ", " + PFDate.time.string(from: record.markedAt))
                        Divider()
                        InfoRow(label: "\(record.item.dateType.title) date", value: PFDate.weekdayLongDay.string(from: record.item.expiry))
                        Divider()
                        InfoRow(label: "Added", value: PFDate.weekdayDay.string(from: record.item.addedOn))
                        Divider()
                        InfoRow(label: "Est. value", value: String(format: "£%.2f", record.item.priceGBP))
                    }
                }
                .padding(20)
            }
            .pfTopBar("Details")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button("Add again") { router.startAddFood(store.draftToAddAgain(record.item)) }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Marked by mistake? Move back to My Food") {
                        store.restore(record)
                        dismiss()
                        toasts.show("\(record.item.name)\nmoved back to My Food", actionTitle: "View") {
                            router.goHome()
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
        } else {
            ContentUnavailableView("Record not found", systemImage: "clock")
        }
    }
}


/// Pick any past month and year in History.
struct MonthPickerSheet: View {
    @Binding var month: Date
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int

    private let cal = Calendar.current

    init(month: Binding<Date>) {
        _month = month
        _year = State(initialValue: Calendar.current.component(.year, from: month.wrappedValue))
    }

    private var thisYear: Int { cal.component(.year, from: .now) }

    private func date(_ m: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: m, day: 1)) ?? .now
    }

    private func isFuture(_ m: Int) -> Bool {
        date(m) > PFDate.startOfMonth(.now)
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button { year -= 1 } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36).background(Circle().fill(Palette.surface))
                }
                .accessibilityLabel("Previous year")
                Spacer()
                Text(String(year)).font(.headline)
                Spacer()
                Button { year += 1 } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36).background(Circle().fill(Palette.surface))
                }
                .disabled(year >= thisYear)
                .opacity(year >= thisYear ? 0.35 : 1)
                .accessibilityLabel("Next year")
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(Palette.ink)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(1...12, id: \.self) { m in
                    let picked = cal.component(.year, from: month) == year && cal.component(.month, from: month) == m
                    Button {
                        month = date(m)
                        dismiss()
                    } label: {
                        Text(cal.shortMonthSymbols[m - 1])
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(picked ? Color.white : Palette.ink)
                            .background(RoundedRectangle(cornerRadius: 12).fill(picked ? Palette.buttonDark : Palette.surface))
                    }
                    .disabled(isFuture(m))
                    .opacity(isFuture(m) ? 0.35 : 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }
}
