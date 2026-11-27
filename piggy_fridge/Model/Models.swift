import Foundation
import UIKit

// MARK: - Date type, storage, outcome

nonisolated enum DateType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case useBy
    case bestBefore
    case notSure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .useBy: "Use By"
        case .bestBefore: "Best Before"
        case .notSure: "Not sure"
        }
    }

    /// Lowercase form used inside sentences and detail rows ("Best before").
    var sentenceTitle: String {
        switch self {
        case .useBy: "Use by"
        case .bestBefore: "Best before"
        case .notSure: "Not sure"
        }
    }

    var helper: String {
        switch self {
        case .useBy: "A safety date. Eat, cook or freeze it by the end of this day."
        case .bestBefore: "A quality date. It’s usually fine after this, so look and smell before you bin it."
        case .notSure: "No problem. We’ll treat it like a Best Before date and remind you to check it."
        }
    }

    var dateFieldLabel: String {
        switch self {
        case .useBy: "Use By date"
        case .bestBefore: "Best Before date"
        case .notSure: "Date on the label"
        }
    }
}

nonisolated enum Storage: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case fridge
    case freezer
    case cupboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .cupboard: "Cupboard"
        }
    }
}

nonisolated enum Outcome: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case eaten
    case frozen
    case thrown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eaten: "Eaten"
        case .frozen: "Frozen"
        case .thrown: "Thrown away"
        }
    }

    var symbol: String {
        switch self {
        case .eaten: "checkmark"
        case .frozen: "snowflake"
        case .thrown: "trash"
        }
    }

    /// Eaten and frozen both count as "saved".
    var isSaved: Bool { self != .thrown }
}

// MARK: - Food item

nonisolated struct FoodItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var iconAsset: String
    var category: String
    var expiry: Date
    var dateType: DateType
    var storage: Storage
    var addedOn: Date = .now
    var weightKg: Double = 0.4
    var priceGBP: Double = 1.6
    var co2eKg: Double = 0.7
    /// Set when the food was frozen from My Food. It already counts as saved in History (that record's id),
    /// so eating it later adds nothing, and throwing it away changes that record to thrown away.
    var frozenRecordID: UUID? = nil
    /// Set when the pack was opened. The date printed on the pack is kept in `printedExpiry`.
    var openedOn: Date? = nil
    var printedExpiry: Date? = nil
}

// MARK: - History

nonisolated struct HistoryRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var item: FoodItem
    var outcome: Outcome
    var markedAt: Date
}

// MARK: - In-app notifications (the bell inbox)

nonisolated struct InboxMessage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var date: Date
    var dateType: DateType?
    var isRead: Bool = false
    var readAt: Date? = nil      // 읽은 날짜 (14일 계산용)
    var itemID: UUID?
    var requestID: String? = nil   // the notification this came from, so it is only added once
}

// MARK: - Reminder settings

nonisolated struct ReminderSettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    /// Use By: an early reminder, `daysBefore` days before the date (1, 2 or 3).
    var dayBefore: Bool = true
    var daysBefore: Int = 2
    /// Use By: also remind on the expiry day itself.
    var onTheDay: Bool = true
    /// Best Before and "Not sure" food: same choices as Use By, but quieter by default
    /// (no early reminder, one on the day). 0 = no early reminder.
    var bestBeforeDaysBefore: Int = 0
    var bestBeforeOnTheDay: Bool = true
    var hour: Int = 8
    var minute: Int = 30

    static let daysBeforeChoices = [1, 2, 3]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, dayBefore, daysBefore, onTheDay, bestBeforeDaysBefore, bestBeforeOnTheDay, hour, minute
        case legacyBestBefore = "bestBefore"     // saved by the previous version ("onTheDay" or "off")
    }

    /// Settings saved by an older version may be missing newer fields.
    /// Fill those in instead of failing, so saved food and settings are never lost after an update.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        dayBefore = try c.decodeIfPresent(Bool.self, forKey: .dayBefore) ?? true
        daysBefore = try c.decodeIfPresent(Int.self, forKey: .daysBefore) ?? 1     // the first version always meant 1 day before
        onTheDay = try c.decodeIfPresent(Bool.self, forKey: .onTheDay) ?? true
        bestBeforeDaysBefore = try c.decodeIfPresent(Int.self, forKey: .bestBeforeDaysBefore) ?? 0
        if let on = try c.decodeIfPresent(Bool.self, forKey: .bestBeforeOnTheDay) {
            bestBeforeOnTheDay = on
        } else {
            let legacy = try c.decodeIfPresent(String.self, forKey: .legacyBestBefore)
            bestBeforeOnTheDay = legacy != "off"
        }
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? 8
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? 30
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(dayBefore, forKey: .dayBefore)
        try c.encode(daysBefore, forKey: .daysBefore)
        try c.encode(onTheDay, forKey: .onTheDay)
        try c.encode(bestBeforeDaysBefore, forKey: .bestBeforeDaysBefore)
        try c.encode(bestBeforeOnTheDay, forKey: .bestBeforeOnTheDay)
        try c.encode(hour, forKey: .hour)
        try c.encode(minute, forKey: .minute)
    }

    var timeDate: Date {
        get {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = parts.hour ?? 8
            minute = parts.minute ?? 30
        }
    }

    var timeLabel: String { PFDate.time.string(from: timeDate) }

    /// "1 day before" / "2 days before"
    static func daysLabel(_ days: Int) -> String { days == 1 ? "1 day before" : "\(days) days before" }
    var daysBeforeLabel: String { Self.daysLabel(daysBefore) }

    /// Which days to remind, for one food: 0 = the expiry day, -2 = two days before.
    func dayOffsets(for type: DateType) -> [Int] {
        var offsets: [Int] = []
        switch type {
        case .useBy:
            if dayBefore { offsets.append(-daysBefore) }
            if onTheDay { offsets.append(0) }
        case .bestBefore, .notSure:
            if bestBeforeDaysBefore > 0 { offsets.append(-bestBeforeDaysBefore) }
            if bestBeforeOnTheDay { offsets.append(0) }
        }
        return offsets
    }

    private var bestBeforeAny: Bool { bestBeforeDaysBefore > 0 || bestBeforeOnTheDay }

    /// True when no food would get any reminder at all.
    var nothingSelected: Bool { !dayBefore && !onTheDay && !bestBeforeAny }

    /// Short line for the reminder prompt card (Use By, the one that matters most).
    var whenLabel: String {
        switch (dayBefore, onTheDay) {
        case (true, true): "\(daysBeforeLabel) · On the day"
        case (true, false): daysBeforeLabel
        case (false, true): "On the day"
        case (false, false): bestBeforeAny ? "Best Before only" : "No reminders selected"
        }
    }

    private static func phrase(early: Int?, onDay: Bool) -> String {
        switch (early, onDay) {
        case (let d?, true): "\(daysLabel(d)) and on the expiry day"
        case (let d?, false): "\(daysLabel(d)) the expiry day"
        case (nil, true): "on the expiry day"
        case (nil, false): "no reminders"
        }
    }

    /// Sentence under the Notifications settings.
    var summary: String {
        if nothingSelected { return "Pick at least one so we know when to remind you." }
        let useBy = Self.phrase(early: dayBefore ? daysBefore : nil, onDay: onTheDay)
        let best = Self.phrase(early: bestBeforeDaysBefore > 0 ? bestBeforeDaysBefore : nil, onDay: bestBeforeOnTheDay)
        return "You’ll get reminders at \(timeLabel). Use By food: \(useBy). Best Before food: \(best)."
    }
}

// MARK: - Account (local mock until a backend exists)

nonisolated enum SignInMethod: String, Codable, Hashable, Sendable {
    case apple, google, email

    var title: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .email: "Email"
        }
    }
}

nonisolated struct Account: Codable, Hashable, Sendable {
    var name: String
    var email: String
    var method: SignInMethod
}

// MARK: - Presets (Resources/FoodPresets.json)

nonisolated struct FoodPreset: Identifiable, Codable, Hashable, Sendable {
    var id: Int
    var name: String
    var category: String
    var storage: Storage
    var dateType: DateType
    var typicalDays: Int
    var freezable: Bool
    var icon: String
    var pack: String
    var note: String
    var weightKg: Double
    var priceGBP: Double
    var co2eKg: Double
}

// MARK: - What changes once a pack is opened

/// Where to keep the food after opening, and how long it lasts. Read from the preset note
/// ("Once opened, fridge 3 days in a container") or from the category (sauces go in the fridge).
nonisolated struct OpenedRule: Hashable, Sendable {
    var storage: Storage
    var days: Int?

    var hint: String {
        let place = storage.title
        guard let days else { return "Keep in the \(place) once opened" }
        let span: String
        if days >= 30, days % 30 == 0 { span = days == 30 ? "1 month" : "\(days / 30) months" }
        else if days >= 7, days % 7 == 0 { span = days == 7 ? "1 week" : "\(days / 7) weeks" }
        else { span = days == 1 ? "1 day" : "\(days) days" }
        return "\(place) · use within \(span)"
    }

    static func parse(note: String, storage: Storage) -> OpenedRule? {
        let n = note.lowercased()
        guard n.contains("opened") || n.contains("once cut") else { return nil }
        var after = storage
        if n.contains("fridge") { after = .fridge }
        var days: Int?
        if let r = n.range(of: "(\\d+)(?:\\s*to\\s*\\d+)?\\s*(day|week|month)", options: .regularExpression) {
            let piece = String(n[r])
            let number = Int(piece.prefix { $0.isNumber }) ?? 0
            if piece.contains("month") { days = number * 30 }
            else if piece.contains("week") { days = number * 7 }
            else { days = number }
        } else if n.contains("a week") { days = 7 }
        if days == nil && after == storage { return nil }
        return OpenedRule(storage: after, days: days)
    }
}

extension FoodPreset {
    /// "Cupboard until opened, then fridge" foods start in the cupboard.
    var storageBeforeOpening: Storage {
        note.lowercased().hasPrefix("cupboard until opened") ? .cupboard : storage
    }

    var openedRule: OpenedRule? { OpenedRule.parse(note: note, storage: storageBeforeOpening) }
}

// MARK: - Draft used by Add food

nonisolated struct AddFoodDraft: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String = ""
    var dateType: DateType = .useBy
    var date: Date? = nil
    var storage: Storage = .fridge
}

// MARK: - Home sections

nonisolated enum FoodSection: Int, CaseIterable, Identifiable, Sendable {
    /// Use by has passed: a safety date, so the app says plainly not to eat it.
    case dontEat
    /// Best before has passed: a quality date, so it is usually still fine to eat.
    case checkIt
    case today
    case soon
    case later

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dontEat: "Don’t eat"
        case .checkIt: "Need to review"
        case .today: "Use today"
        case .soon: "Expiring soon"
        case .later: "Later"
        }
    }

    /// One short line under the section title that explains the date.
    var note: String? {
        switch self {
        default: nil
        }
    }

    static func section(forDaysLeft days: Int, dateType: DateType) -> FoodSection {
        switch days {
        case ..<0: dateType == .useBy ? .dontEat : .checkIt
        case 0: .today
        case 1...4: .soon
        default: .later
        }
    }

    static func section(for item: FoodItem) -> FoodSection {
        section(forDaysLeft: PFDate.daysLeft(until: item.expiry), dateType: item.dateType)
    }
}
