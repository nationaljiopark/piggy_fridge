import Foundation
import UIKit

/// Date formatting and day maths used across the app.
/// Formats follow the Figma copy (British English: "22 Apr", "Thu 23 Apr 2026", "8:30 AM").
nonisolated enum PFDate {
    nonisolated(unsafe) static let shortDay = make("d MMM")
    nonisolated(unsafe) static let longDay = make("d MMM yyyy")
    nonisolated(unsafe) static let weekdayDay = make("EEE d MMM")
    nonisolated(unsafe) static let weekdayLongDay = make("EEE d MMM yyyy")
    nonisolated(unsafe) static let weekday = make("EEEE")
    nonisolated(unsafe) static let month = make("MMMM yyyy")
    nonisolated(unsafe) static let monthName = make("MMMM")
    nonisolated(unsafe) static let time: DateFormatter = {
        let f = make("h:mm a")
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f
    }()

    static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = format
        return f
    }

    /// Monday-first calendar, like the Figma calendar.
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "en_GB")
        return c
    }

    static func daysLeft(until date: Date, from now: Date = .now) -> Int {
        let c = Calendar.current
        return c.dateComponents([.day], from: c.startOfDay(for: now), to: c.startOfDay(for: date)).day ?? 0
    }

    /// "1 day ago", "Today", "Tomorrow", "3 days"
    static func relativeLabel(daysLeft days: Int) -> String {
        switch days {
        case ..<(-1): "\(-days) days ago"
        case -1: "1 day ago"
        case 0: "Today"
        case 1: "Tomorrow"
        case 60...: "\(days / 30) months"   // frozen food: "3 months" reads better than "91 days"
        default: "\(days) days"
        }
    }

    /// "Today", "Yesterday" or "Sun 18 Oct"
    static func dayHeader(for date: Date) -> String {
        let c = Calendar.current
        if c.isDateInToday(date) { return "Today" }
        if c.isDateInYesterday(date) { return "Yesterday" }
        return weekdayDay.string(from: date)
    }

    /// "Thu 23 Apr 2026 · Tomorrow"
    static func fieldLabel(for date: Date) -> String {
        let days = daysLeft(until: date)
        let base = weekdayLongDay.string(from: date)
        switch days {
        case 0: return base + " · Today"
        case 1: return base + " · Tomorrow"
        default: return base
        }
    }

    static func addingDays(_ days: Int, to date: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: date)) ?? date
    }

    static func startOfMonth(_ date: Date) -> Date {
        let c = calendar
        return c.date(from: c.dateComponents([.year, .month], from: date)) ?? date
    }

    static func addingMonths(_ months: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: months, to: startOfMonth(date)) ?? date
    }

    static func isSameMonth(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }

    /// Cells for a Monday-first month grid. `nil` = empty cell.
    static func monthGrid(for month: Date) -> [Date?] {
        let c = calendar
        let start = startOfMonth(month)
        let days = c.range(of: .day, in: .month, for: start)?.count ?? 30
        let weekday = c.component(.weekday, from: start) // 1 = Sunday
        let offset = (weekday + 5) % 7                    // Monday = 0
        var cells: [Date?] = Array(repeating: nil, count: offset)
        for d in 0..<days {
            cells.append(c.date(byAdding: .day, value: d, to: start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}
