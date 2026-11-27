import Foundation
import Charts
import SwiftUI

/// Which number the Summary screen is about (the four tiles on My).
enum SummaryMetric: String, CaseIterable, Identifiable, Hashable {
    case items, value, food, co2e
    var id: String { rawValue }

    var tab: String {
        switch self {
        case .items: "Items"
        case .value: "Value"
        case .food: "Food"
        case .co2e: "CO2e"
        }
    }

    var bigLabel: String {
        switch self {
        case .items: "Items saved"
        case .value: "Est. value saved"
        case .food: "Est. food saved"
        case .co2e: "Est. CO2e impact"
        }
    }

    /// Value of one saved record for this metric.
    func amount(_ record: HistoryRecord) -> Double {
        switch self {
        case .items: 1
        case .value: record.item.priceGBP
        case .food: record.item.weightKg
        case .co2e: record.item.co2eKg
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .items: "\(Int(v.rounded()))"
        case .value: String(format: "£%.2f", v)
        case .food, .co2e: String(format: "%.1fkg", v)
        }
    }

    /// Short form for the chart scale on the right.
    func axis(_ v: Double) -> String {
        switch self {
        case .items: "\(Int(v))"
        case .value: "£\(Int(v))"
        case .food, .co2e: v == 0 ? "0" : String(format: "%.1f", v)
        }
    }

    var infoTitle: String { self == .items ? "What counts" : "How we estimate" }

    var info: String {
        switch self {
        case .items: "Items saved counts food you marked as Eaten or Frozen. Food you mark as Thrown away is shown separately."
        case .value: "We use the price read from the label. If there isn't one, we use a typical UK supermarket price."
        case .food: "We use the weight on the label. If there isn't one, we use a typical pack size for that food."
        case .co2e: "CO2e is the greenhouse gas avoided by not wasting food. We use typical figures per kg for each type of food."
        }
    }
}

/// Summary detail: opened from a tile on My. Items / Value / Food / CO2e for one month.
struct SummaryView: View {
    @Environment(AppStore.self) private var store
    @State private var metric: SummaryMetric
    @State private var month: Date = PFDate.startOfMonth(.now)
    @State private var showMonthPicker = false
    /// How many weekly bars have grown in so far (they grow one by one when the screen opens).
    @State private var revealed = 0

    static let dark = Palette.inkSecondary
    static let light = Color(red: 213 / 255, green: 214 / 255, blue: 216 / 255)   // #D5D6D8

    init(metric: SummaryMetric) {
        _metric = State(initialValue: metric)
    }

    // MARK: Data

    private var records: [HistoryRecord] { store.records(inMonthOf: month) }
    private var saved: [HistoryRecord] { records.filter { $0.outcome.isSaved } }
    private var thrown: [HistoryRecord] { records.filter { !$0.outcome.isSaved } }

    private var previousMonth: Date {
        PFDate.calendar.date(byAdding: .month, value: -1, to: month) ?? month
    }
    private var isCurrentMonth: Bool { PFDate.isSameMonth(month, .now) }

    private func total(_ list: [HistoryRecord]) -> Double { list.reduce(0) { $0 + metric.amount($1) } }

    private struct Week: Identifiable {
        let id: Int
        let label: String
        var value = 0.0
        var eaten = 0
        var thrown = 0
    }

    private var weeks: [Week] {
        let labels = store.weeklyStats(for: month).map(\.label)
        var list = labels.enumerated().map { Week(id: $0.offset, label: $0.element) }
        guard !list.isEmpty else { return [] }
        for r in records {
            let day = PFDate.calendar.component(.day, from: r.markedAt)
            let i = min((day - 1) / 7, list.count - 1)
            if r.outcome.isSaved {
                list[i].value += metric.amount(r)
                list[i].eaten += 1
            } else {
                list[i].thrown += 1
            }
        }
        return list
    }

    /// The week that contains today (only in the current month).
    private var thisWeek: Int? {
        guard isCurrentMonth else { return nil }
        return (PFDate.calendar.component(.day, from: .now) - 1) / 7
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                segmented
                monthBar
                headline
                if records.isEmpty {
                    Text("No records this month.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    chart
                    categories
                    topList
                }
                infoBox
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Palette.ink)
        .pfTopBar("Summary")
        .sheet(isPresented: $showMonthPicker) {
            SummaryMonthSheet(selected: $month)
                .presentationDetents([.height(440)])
                .presentationCornerRadius(20)
        }
    }

    // MARK: Pieces

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(SummaryMetric.allCases) { m in
                Button {
                    withAnimation(.snappy) { metric = m }
                } label: {
                    Text(m.tab)
                        .font(.subheadline.weight(m == metric ? .semibold : .medium))
                        .foregroundStyle(m == metric ? Palette.ink : Palette.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if m == metric {
                                Capsule().fill(Color.white).shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Palette.surface))
    }

    private var monthBar: some View {
        HStack {
            Button { month = previousMonth } label: {
                Image(systemName: "chevron.left").frame(width: 32, height: 32)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Button { showMonthPicker = true } label: {
                HStack(spacing: 4) {
                    Text(PFDate.make("MMMM yyyy").string(from: month)).font(.headline)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
            }
            Spacer()
            Button {
                month = PFDate.calendar.date(byAdding: .month, value: 1, to: month) ?? month
            } label: {
                Image(systemName: "chevron.right").frame(width: 32, height: 32)
            }
            .disabled(isCurrentMonth)
            .accessibilityLabel("Next month")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ink)
    }

    private var headline: some View {
        let now = total(saved)
        let before = total(store.records(inMonthOf: previousMonth).filter { $0.outcome.isSaved })
        let diff = now - before
        let prevName = PFDate.monthName.string(from: previousMonth)
        let delta: String
        if abs(diff) < 0.005 {
            delta = "Same as \(prevName)"
        } else if metric == .items {
            delta = diff > 0 ? "▲ \(Int(diff)) more than \(prevName)" : "▼ \(Int(-diff)) fewer than \(prevName)"
        } else {
            delta = diff > 0 ? "▲ \(metric.format(diff)) vs \(prevName)" : "▼ \(metric.format(-diff)) vs \(prevName)"
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(metric.bigLabel).font(.footnote.weight(.medium)).foregroundStyle(Palette.inkSecondary)
            Text(metric.format(now)).font(.system(size: 44, weight: .bold))
            Text(delta).font(.footnote).foregroundStyle(Palette.inkSecondary)
        }
    }

    private var chart: some View {
        let list = weeks
        let average = list.isEmpty ? 0 : list.map(\.value).reduce(0, +) / Double(list.count)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric == .items ? "Eaten vs thrown" : "By week").font(.headline)
                Spacer()
                Text(metric == .items ? "\(percentSaved)% saved" : "avg \(metric.format(average))")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            if metric == .items {
                Text("\(saved.count) saved · \(thrown.count) thrown this month")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            let top = max(1, list.map { metric == .items ? Double($0.eaten + $0.thrown) : $0.value }.max() ?? 1)
            Chart {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, w in
                    // 0 until this bar's turn, then it grows to its real height.
                    let k: Double = i < revealed ? 1 : 0
                    if metric == .items {
                        // Two bars with the same week stack: saved at the bottom, thrown on top.
                        BarMark(x: .value("Week", w.label), y: .value("Count", Double(w.eaten) * k), width: .fixed(28))
                            .foregroundStyle(Self.dark)
                        BarMark(x: .value("Week", w.label), y: .value("Count", Double(w.thrown) * k), width: .fixed(28))
                            .foregroundStyle(Self.light)
                    } else {
                        BarMark(x: .value("Week", w.label), y: .value("Amount", w.value * k), width: .fixed(28))
                            .foregroundStyle(w.id == thisWeek ? Self.dark : Self.light)
                            .cornerRadius(6)
                            .annotation(position: .top) {
                                if w.id == thisWeek {
                                    Text(metric.format(w.value)).font(.footnote.weight(.medium)).foregroundStyle(Palette.ink)
                                }
                            }
                    }
                }
                if metric != .items && average > 0 && revealed >= list.count {
                    RuleMark(y: .value("Average", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Palette.chartGray)
                        .annotation(position: .top, alignment: .leading) {
                            Text("avg").font(.caption2.weight(.medium)).foregroundStyle(Palette.chartGray)
                        }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.black.opacity(0.06))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(metric.axis(v)).font(.caption2).foregroundStyle(Palette.chartGray)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            let current = list.first { $0.label == label }?.id == thisWeek
                            Text(label)
                                .font(.caption2.weight(current ? .medium : .regular))
                                .foregroundStyle(current ? Palette.ink : Palette.chartGray)
                        }
                    }
                }
            }
            .chartYScale(domain: 0...top)
            .chartLegend(.hidden)
            .frame(height: 170)
            .task(id: "\(metric)-\(month)") {
                // Bars grow in one after another, left to right.
                revealed = 0
                try? await Task.sleep(for: .milliseconds(200))
                for i in 1...max(weeks.count, 1) {
                    withAnimation(.easeOut(duration: 0.45)) { revealed = i }
                    try? await Task.sleep(for: .milliseconds(130))
                }
            }
            if metric == .items {
                HStack(spacing: 14) {
                    legend(Self.dark, "Saved")
                    legend(Self.light, "Thrown")
                }
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private struct CategoryTotal: Identifiable {
        let name: String
        let value: Double
        var id: String { name }
    }

    private struct ThrownCount: Identifiable {
        let record: HistoryRecord
        let count: Int
        var id: UUID { record.id }
    }

    private var percentSaved: Int {
        records.isEmpty ? 0 : Int((Double(saved.count) / Double(records.count) * 100).rounded())
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }

    private var categories: some View {
        let groups = Dictionary(grouping: saved) { $0.item.category.isEmpty ? "Other" : $0.item.category }
            .map { CategoryTotal(name: $0.key, value: total($0.value)) }
            .sorted { $0.value > $1.value }
            .prefix(5)
        let top = groups.first?.value ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            Text("By category").font(.pfSection)
            ForEach(Array(groups)) { g in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(g.name).font(.subheadline)
                        Spacer()
                        Text(metric.format(g.value)).font(.subheadline.weight(.semibold))
                    }
                    Capsule()
                        .fill(Color(red: 228 / 255, green: 230 / 255, blue: 232 / 255))
                        .frame(height: 6)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(Palette.ink)
                                    .frame(width: geo.size.width * (top > 0 ? g.value / top : 0))
                            }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Rebuild this block when the tab or month changes, with no move animation, so rows
        // can never slide over each other (the "dancing" Dairy & eggs / Bakery overlap).
        .id("\(metric.rawValue)-\(month.timeIntervalSince1970)")
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private var topList: some View {
        if metric == .items {
            let counts = Dictionary(grouping: thrown, by: { $0.item.name })
                .map { ThrownCount(record: $0.value[0], count: $0.value.count) }
                .sorted { $0.count > $1.count }
                .prefix(3)
            if !counts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Most often thrown").font(.pfSection)
                    ForEach(Array(counts)) { entry in
                        row(entry.record,
                            subtitle: entry.count == 1 ? "Thrown once this month" : "Thrown \(entry.count) times this month",
                            trailing: "×\(entry.count)")
                    }
                }
            }
        } else {
            let top = saved.sorted { metric.amount($0) > metric.amount($1) }.prefix(3)
            VStack(alignment: .leading, spacing: 12) {
                Text("Top saved").font(.pfSection)
                ForEach(Array(top), id: \.id) { r in
                    row(r,
                        subtitle: "\(r.outcome == .frozen ? "Frozen" : "Eaten") · \(PFDate.make("d MMM").string(from: r.markedAt))",
                        trailing: metric.format(metric.amount(r)))
                }
            }
        }
    }

    private func row(_ r: HistoryRecord, subtitle: String, trailing: String) -> some View {
        HStack(spacing: 14) {
            FoodIconView(asset: r.item.iconAsset, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.item.name).font(.subheadline)
                Text(subtitle).font(.caption).foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            Text(trailing).font(.subheadline.weight(.semibold))
        }
    }

    private var infoBox: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Palette.inkSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.infoTitle).font(.caption.weight(.semibold))
                Text(metric.info).font(.caption).foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
    }
}

/// "Choose month" sheet: year arrows and a 3 × 4 grid. Months with no records and future months are greyed out.
struct SummaryMonthSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Date
    @State private var year = PFDate.calendar.component(.year, from: .now)

    private let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private func date(_ monthIndex: Int) -> Date {
        PFDate.calendar.date(from: DateComponents(year: year, month: monthIndex + 1, day: 1)) ?? .now
    }

    private func hasRecords(_ d: Date) -> Bool {
        store.history.contains { PFDate.isSameMonth($0.markedAt, d) } || PFDate.isSameMonth(d, .now)
    }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Text("Choose month").font(.headline)
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Palette.surface))
                    }
                    .accessibilityLabel("Close")
                }
            }
            HStack(spacing: 24) {
                Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                Text(String(year)).font(.headline).monospacedDigit()
                Button { year += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(year >= PFDate.calendar.component(.year, from: .now))
            }
            .buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(0..<12, id: \.self) { i in
                    let d = date(i)
                    let isSelected = PFDate.isSameMonth(d, selected)
                    let enabled = d <= .now && hasRecords(d)
                    Button {
                        selected = d
                        dismiss()
                    } label: {
                        Text(names[i])
                            .font(.body.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.white : (enabled ? Palette.ink : Palette.chartGray.opacity(0.6)))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Palette.ink : (enabled ? Palette.surface : Color.clear)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                }
            }
            Text("Months with no records are greyed out.")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(20)
        .foregroundStyle(Palette.ink)
        .onAppear { year = PFDate.calendar.component(.year, from: selected) }
    }
}
//  SummaryView.swift
//  piggy_fridge
//
//  Created by Jio Park on 11/11/2026.
//

import Foundation
