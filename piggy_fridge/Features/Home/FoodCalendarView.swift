import Foundation
import SwiftUI
import UIKit

/// Calendar mode of My Food: month grid with Use By / Best Before dots, and the selected day's food.
struct FoodCalendarView: View {
    @Environment(AppStore.self) private var store
    @State private var month = PFDate.startOfMonth(.now)
    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: .now)
    /// +1 when going to the next month (the new month comes in from the right), -1 for the previous month.
    @State private var direction = 1

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            monthHeader
            legend
            // The grid slides sideways when the month changes (same ease in as List / Calendar, no scaling).
            ZStack(alignment: .top) {
                grid
                    .id(month)
                    .transition(.asymmetric(
                        insertion: .move(edge: direction > 0 ? .trailing : .leading),
                        removal: .move(edge: direction > 0 ? .leading : .trailing)))
            }
            .clipped()
            // Swipe left for next month, swipe right for the previous month.
            .simultaneousGesture(
                DragGesture(minimumDistance: 24, coordinateSpace: .local)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
                              abs(value.translation.width) > 40 else { return }
                        changeMonth(value.translation.width < 0 ? 1 : -1)
                    }
            )
            Rectangle().fill(Palette.surface).frame(height: 8).padding(.top, 4)
            selectedDayList
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(PFDate.month.string(from: month)).font(.title3.weight(.bold))
            Spacer()
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 40, height: 40)
            }
            .accessibilityLabel("Previous month")
            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 40, height: 40)
            }
            .accessibilityLabel("Next month")
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 20)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle().fill(Palette.ink).frame(width: 7, height: 7)
                Text("Use By")
            }
            HStack(spacing: 6) {
                Circle().strokeBorder(Palette.ink, lineWidth: 1.4).frame(width: 7, height: 7)
                Text("Best Before")
            }
        }
        .font(.caption)
        .padding(.horizontal, 20)
    }

    private var grid: some View {
        let cells = PFDate.monthGrid(for: month)
        return VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdays[i]).font(.caption.weight(.medium)).foregroundStyle(Palette.inkTertiary)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 52)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isPast = calendar.startOfDay(for: day) < calendar.startOfDay(for: .now)
        let isToday = calendar.isDateInToday(day)
        let dayItems = store.items(on: day)

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(isToday ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.white : (isPast ? Palette.inkDisabled : Palette.ink))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isSelected ? Palette.buttonDark : Color.clear))
                    .overlay(Circle().strokeBorder(isToday && !isSelected ? Palette.ink : Color.clear, lineWidth: 1))
                HStack(spacing: 3) {
                    // One dot per food, up to 3. More than 3: two dots and "+N".
                    let shown = dayItems.count > 3 ? 2 : dayItems.count
                    ForEach(0..<shown, id: \.self) { i in
                        if dayItems[i].dateType == .useBy {
                            Circle().fill(Palette.ink).frame(width: 6, height: 6)
                        } else {
                            Circle().strokeBorder(Palette.ink, lineWidth: 1.2).frame(width: 6, height: 6)
                        }
                    }
                    if dayItems.count > 3 {
                        Text("+\(dayItems.count - 2)").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.ink)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PFDate.weekdayLongDay.string(from: day) + (dayItems.isEmpty ? "" : ", \(dayItems.count) due"))
    }

    @ViewBuilder
    private var selectedDayList: some View {
        if let day = selectedDay, PFDate.isSameMonth(day, month) {
            let items = store.items(on: day)
            VStack(alignment: .leading, spacing: 0) {
                Text(PFDate.weekdayDay.string(from: day))
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                if items.isEmpty {
                    Text("Nothing is due on this day.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkTertiary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                } else {
                    ForEach(items) { item in
                        NavigationLink(value: HomeRoute.item(item.id)) { FoodCardRow(item: item).id(item.hashValue) }
                            .buttonStyle(.plain)
                    }
                }
            }
        } else {
            Text("Dots show the days when food is due.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkTertiary)
                .padding(.horizontal, 20)
        }
    }

    private func changeMonth(_ delta: Int) {
        direction = delta
        withAnimation(.easeIn(duration: 0.3)) {
            month = PFDate.addingMonths(delta, to: month)
            selectedDay = PFDate.isSameMonth(.now, month) ? Calendar.current.startOfDay(for: .now) : nil
        }
    }
}
