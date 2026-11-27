import Foundation
import Observation
import UIKit

/// Single source of truth for the app. Saved as JSON in the app's Documents folder.
@Observable
final class AppStore {
    /// One store for the whole app. The notification delegate uses it too, so a lock screen
    /// action works even when the app was closed and is only waking up in the background.
    static let shared = AppStore()

    var items: [FoodItem] = []
    var history: [HistoryRecord] = []
    var inbox: [InboxMessage] = []
    var reminders = ReminderSettings()
    var account: Account?
    var hasSeenCoachTip = false
    var hasAskedReminders = false
    /// First name used in "Welcome, ...". Stored on this iPhone only. Empty = not set.
    var userName = ""
    var hasAskedName = false

    @ObservationIgnored let presets: [FoodPreset]
    @ObservationIgnored private var lastRemoved: (item: FoodItem, record: HistoryRecord?)?
    @ObservationIgnored private var lastDeletedRecord: (record: HistoryRecord, index: Int, frozenItemID: UUID?)?

    init() {
        presets = AppStore.loadPresets()
        if let snapshot = AppStore.loadSnapshot() {
            items = snapshot.items
            history = snapshot.history
            inbox = snapshot.inbox
            reminders = snapshot.reminders
            account = snapshot.account
            hasSeenCoachTip = snapshot.hasSeenCoachTip
            hasAskedReminders = snapshot.hasAskedReminders
            userName = snapshot.userName ?? ""
            hasAskedName = snapshot.hasAskedName ?? false
        }
        // A new install starts empty, so the first-time Home (Welcome, How it works) shows.
        // Sample data: Profile > Developer > "Load sample data" (debug builds only).
    }

    // MARK: - Derived

    var sortedItems: [FoodItem] { items.sorted { $0.expiry < $1.expiry } }

    func items(in section: FoodSection) -> [FoodItem] {
        sortedItems.filter { FoodSection.section(for: $0) == section }
    }

    func items(on day: Date) -> [FoodItem] {
        sortedItems.filter { Calendar.current.isDate($0.expiry, inSameDayAs: day) }
    }

    func item(with id: UUID) -> FoodItem? { items.first { $0.id == id } }

    func search(_ query: String) -> [FoodItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        func fold(_ text: String) -> String {
            text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        }
        let words = q.split(whereSeparator: { $0.isWhitespace }).map { fold(String($0)) }
        return sortedItems.filter { item in
            let haystack = fold(item.name + " " + item.category)
            return words.allSatisfy { word in
                // "eggs" also finds "Egg", "tomatoes" finds "Tomato"
                haystack.contains(word) || (word.count > 3 && word.hasSuffix("s") && haystack.contains(String(word.dropLast())))
            }
        }
    }

    var unreadCount: Int { inbox.filter { !$0.isRead }.count }

    func preset(named name: String) -> FoodPreset? {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !n.isEmpty else { return nil }
        if let exact = presets.first(where: { $0.name.lowercased() == n }) { return exact }
        // "Semi-skimmed milk 2 pints" -> Milk
        return presets
            .filter { n.contains($0.name.lowercased()) || $0.name.lowercased().contains(n) }
            .max { $0.name.count < $1.name.count }
    }

    func suggestions(for text: String) -> [FoodPreset] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return Array(presets.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(6))
    }

    // MARK: - Food

    func makeItem(from draft: AddFoodDraft) -> FoodItem {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        let preset = preset(named: name)
        return FoodItem(
            name: name,
            iconAsset: preset?.icon ?? "food_unknown_food",
            category: preset?.category ?? "Other",
            expiry: draft.date ?? .now,
            dateType: draft.dateType,
            storage: draft.storage,
            addedOn: .now,
            weightKg: preset?.weightKg ?? 0.4,
            priceGBP: preset?.priceGBP ?? 1.6,
            co2eKg: preset?.co2eKg ?? 0.7
        )
    }

    /// What happens when a pack is opened: where it should be kept and how long it lasts.
    func openedRule(for item: FoodItem) -> OpenedRule? {
        if let rule = preset(named: item.name)?.openedRule { return rule }
        if item.category == "Sauces" { return OpenedRule(storage: .fridge, days: nil) }
        return nil
    }

    /// Marks a pack as opened: moves it to where it should be kept and, if it only lasts a few days once opened,
    /// shortens the date. The printed date is kept so Undo can put everything back.
    @discardableResult
    func markOpened(_ id: UUID) -> FoodItem? {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].openedOn == nil,
              let rule = openedRule(for: items[i]) else { return nil }
        let before = items[i]
        var item = before
        let today = Calendar.current.startOfDay(for: .now)
        item.openedOn = today
        item.printedExpiry = before.expiry
        item.storage = rule.storage
        if let days = rule.days {
            let limit = PFDate.addingDays(days, to: today)
            if limit < item.expiry {
                item.expiry = limit
                item.dateType = .useBy
            }
        }
        items[i] = item
        changed()
        return before
    }

    func add(_ item: FoodItem) {
        items.append(item)
        changed()
    }

    func update(_ item: FoodItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = item
        changed()
    }

    /// Removes the item without recording an outcome. Returns it for Undo.
    @discardableResult
    func delete(_ id: UUID) -> FoodItem? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = items.remove(at: i)
        lastRemoved = (removed, nil)
        changed()
        return removed
    }

    /// How long frozen food keeps its best quality, in months (lower end of each range).
    /// Frozen food kept at -18°C stays safe; these times are for quality only.
    /// Sources: USDA FoodSafety.gov cold food storage chart (meat, poultry, fish, leftovers, soup),
    /// UK FSA "How to chill, freeze and defrost food safely" (about 3 months for other foods).
    static let freezerMonthsByFood: [String: Int] = [
        "whole chicken": 12,
        "chicken breasts": 9, "chicken thighs": 9,
        "beef mince": 3, "pork mince": 3,
        "beef steak": 4, "pork chops": 4,
        "sausages": 1, "bacon": 1, "sliced ham": 1, "chorizo": 1,
        "salmon fillets": 2, "smoked salmon": 2, "smoked mackerel": 2,
        "cod fillets": 6, "fish fingers": 6, "cooked prawns": 6,
        "leftovers": 2, "ready meal": 2, "cooked rice": 2, "fresh soup": 2,
    ]

    /// Months a food keeps its quality in the freezer: the food itself, then its category, then 3 months.
    func freezerMonths(for item: FoodItem) -> Int {
        if let preset = preset(named: item.name),
           let months = Self.freezerMonthsByFood[preset.name.lowercased()] { return months }
        switch item.category {
        case "Meat", "Fish": return 2      // FSA: meat about 2 to 3 months
        default: return 3                  // FSA: baked goods, fruit and vegetables about 3 to 4 months
        }
    }

    /// Marks an item as eaten / frozen / thrown away.
    /// Frozen counts as saved but keeps the food in My Food, moved to the Freezer with a new date,
    /// so it is not forgotten at the back of the freezer.
    @discardableResult
    func mark(_ id: UUID, as outcome: Outcome) -> FoodItem? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        let before = items[i]

        if outcome == .frozen {
            let record = HistoryRecord(item: before, outcome: .frozen, markedAt: .now)
            history.insert(record, at: 0)
            var frozen = before
            frozen.storage = .freezer
            frozen.dateType = .bestBefore
            frozen.expiry = Calendar.current.date(byAdding: .month, value: freezerMonths(for: before),
                                                  to: Calendar.current.startOfDay(for: .now)) ?? before.expiry
            frozen.frozenRecordID = record.id
            items[i] = frozen
            lastRemoved = (before, record)
            changed()
            return before
        }

        let removed = items.remove(at: i)
        if let frozenID = removed.frozenRecordID {
            // Already counted as saved when it was frozen.
            if outcome == .thrown, let r = history.firstIndex(where: { $0.id == frozenID }) {
                history[r].outcome = .thrown
                history[r].markedAt = .now
            }
            lastRemoved = (removed, nil)
        } else {
            let record = HistoryRecord(item: removed, outcome: outcome, markedAt: .now)
            history.insert(record, at: 0)
            lastRemoved = (removed, record)
        }
        changed()
        return removed
    }

    func undoLastRemoval() {
        guard let last = lastRemoved else { return }
        items.removeAll { $0.id == last.item.id }
        items.append(last.item)
        if let record = last.record { history.removeAll { $0.id == record.id } }
        if let frozenID = last.item.frozenRecordID, let r = history.firstIndex(where: { $0.id == frozenID }) {
            history[r].outcome = .frozen
        }
        lastRemoved = nil
        changed()
    }

    /// "Marked by mistake? Move back to My Food"
    func restore(_ record: HistoryRecord) {
        // A frozen item is still in My Food (in the Freezer): move that same item back, never add a second copy.
        if let i = items.firstIndex(where: { $0.frozenRecordID == record.id }) {
            var original = record.item
            original.frozenRecordID = nil
            items[i] = original
        } else if !items.contains(where: { $0.id == record.item.id }) {
            items.append(record.item)
        }
        history.removeAll { $0.id == record.id }
        changed()
    }

    /// History > swipe to Delete: removes one record for good. The monthly summary updates too.
    /// If the record is for food that is still in the Freezer, that food stays in My Food and
    /// is counted again when it is finally eaten or thrown away.
    func deleteRecord(_ id: UUID) {
        guard let r = history.firstIndex(where: { $0.id == id }) else { return }
        let record = history.remove(at: r)
        var frozenItemID: UUID?
        if let i = items.firstIndex(where: { $0.frozenRecordID == id }) {
            items[i].frozenRecordID = nil
            frozenItemID = items[i].id
        }
        lastDeletedRecord = (record, r, frozenItemID)
        changed()
    }

    /// Undo on the "deleted" toast: puts the record back where it was.
    func undoDeleteRecord() {
        guard let last = lastDeletedRecord else { return }
        history.insert(last.record, at: min(last.index, history.count))
        if let itemID = last.frozenItemID, let i = items.firstIndex(where: { $0.id == itemID }) {
            items[i].frozenRecordID = last.record.id
        }
        lastDeletedRecord = nil
        changed()
    }

    func draftToAddAgain(_ item: FoodItem) -> AddFoodDraft {
        let days = preset(named: item.name)?.typicalDays ?? 1
        return AddFoodDraft(name: item.name, dateType: item.dateType, date: PFDate.addingDays(max(days, 1)), storage: item.storage)
    }

    // MARK: - History summaries

    func records(inMonthOf month: Date) -> [HistoryRecord] {
        history.filter { PFDate.isSameMonth($0.markedAt, month) }.sorted { $0.markedAt > $1.markedAt }
    }

    struct MonthSummary {
        var savedCount = 0
        var thrownCount = 0
        var valueSaved = 0.0
        var weightSaved = 0.0
        var co2Saved = 0.0
    }

    func summary(for month: Date) -> MonthSummary {
        var s = MonthSummary()
        for r in records(inMonthOf: month) {
            if r.outcome.isSaved {
                s.savedCount += 1
                s.valueSaved += r.item.priceGBP
                s.weightSaved += r.item.weightKg
                s.co2Saved += r.item.co2eKg
            } else {
                s.thrownCount += 1
            }
        }
        return s
    }

    struct WeekStat: Identifiable {
        var id: String { label }
        var label: String
        var eaten: Int
        var thrown: Int
    }

    func weeklyStats(for month: Date) -> [WeekStat] {
        let c = PFDate.calendar
        let start = PFDate.startOfMonth(month)
        let days = c.range(of: .day, in: .month, for: start)?.count ?? 30
        let weekCount = Int((Double(days) / 7).rounded(.up))
        var stats = (1...weekCount).map { WeekStat(label: "W\($0)", eaten: 0, thrown: 0) }
        for r in records(inMonthOf: month) {
            let day = c.component(.day, from: r.markedAt)
            let index = min((day - 1) / 7, weekCount - 1)
            if r.outcome.isSaved { stats[index].eaten += 1 } else { stats[index].thrown += 1 }
        }
        return stats
    }

    // MARK: - Inbox

    /// Mark all read: the notifications are cleared from the list. Undo brings them back.
    private var clearedInbox: [InboxMessage] = []

    func clearInbox() {
        guard !inbox.isEmpty else { return }
        clearedInbox = inbox
        inbox = []
        changed()
    }

    func undoClearInbox() {
        guard !clearedInbox.isEmpty else { return }
        inbox = clearedInbox
        clearedInbox = []
        changed()
    }

    func markAllRead() {
        for i in inbox.indices where !inbox[i].isRead {
            inbox[i].isRead = true
            inbox[i].readAt = .now
        }
        changed()
    }

    func markRead(_ id: UUID) {
        guard let i = inbox.firstIndex(where: { $0.id == id }) else { return }
        if !inbox[i].isRead {
            inbox[i].isRead = true
            inbox[i].readAt = .now
        }
        changed()
    }

    /// 알림 하나 삭제 (밀어서 Delete)
    func deleteMessage(_ id: UUID) {
        inbox.removeAll { $0.id == id }
        changed()
    }

    /// 읽은 지 14일 지난 알림 자동 삭제
    func removeOldReadMessages() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let before = inbox.count
        inbox.removeAll { message in
            guard message.isRead else { return false }          // 안 읽은 건 남김
            let readDate = message.readAt ?? message.date       // 예전 알림은 받은 날짜 기준
            return readDate < cutoff
        }
        if inbox.count != before { changed() }
    }
    // MARK: - Reminders

    func updateReminders(_ settings: ReminderSettings) {
        reminders = settings
        changed()
    }

    func handleNotificationAction(_ action: String, itemID: UUID) {
        switch action {
        case "EATEN": mark(itemID, as: .eaten)
        case "FROZEN": mark(itemID, as: .frozen)
        case "DELETE": delete(itemID)
        default: break // STILL_GOOD or opening the app keeps the item
        }
    }

    // MARK: - Account (mock, local only)

    func signIn(name: String, email: String, method: SignInMethod) {
        account = Account(name: name, email: email, method: method)
        changed()
    }

    func rename(_ name: String) {
        account?.name = name
        setUserName(name)
    }

    /// Saves the first name (or clears it when empty).
    func setUserName(_ name: String) {
        userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        hasAskedName = true
        changed()
    }

    /// My > History > Reset: removes every history record. Food still in My Food stays;
    /// frozen items lose their link to the deleted record.
    func resetHistory() {
        history = []
        for i in items.indices { items[i].frozenRecordID = nil }
        lastDeletedRecord = nil
        changed()
    }

    func signOut() {
        account = nil
        changed()
    }

    func deleteAccount() {
        if let email = account?.email { Credentials.remove(email: email) }
        account = nil
        items = []
        history = []
        inbox = []
        reminders = ReminderSettings()
        hasAskedReminders = false
        userName = ""
        hasAskedName = false
        changed()
    }

    func exportData() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PiggyFridge-data.json")
        guard let data = try? AppStore.encoder.encode(snapshot) else { return nil }
        try? data.write(to: url)
        return url
    }

    // MARK: - Persistence

    nonisolated private struct Snapshot: Codable {
        var items: [FoodItem]
        var history: [HistoryRecord]
        var inbox: [InboxMessage]
        var reminders: ReminderSettings
        var account: Account?
        var hasSeenCoachTip: Bool
        var hasAskedReminders: Bool
        var userName: String?
        var hasAskedName: Bool?
    }

    private var snapshot: Snapshot {
        Snapshot(items: items, history: history, inbox: inbox, reminders: reminders, account: account,
                 hasSeenCoachTip: hasSeenCoachTip, hasAskedReminders: hasAskedReminders,
                 userName: userName, hasAskedName: hasAskedName)
    }

    private static var fileURL: URL {
        URL.documentsDirectory.appendingPathComponent("piggyfridge.json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Call after every change: saves and refreshes scheduled reminders.
    func changed() {
        if let data = try? AppStore.encoder.encode(snapshot) {
            try? data.write(to: AppStore.fileURL, options: .atomic)
        }
        ReminderScheduler.reschedule(items: items, settings: reminders)
    }

    private static func loadSnapshot() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        if let snapshot = try? decoder.decode(Snapshot.self, from: data) { return snapshot }
        // The file exists but could not be read (for example after an update). Keep a copy so the
        // next save cannot wipe the user's food, then start fresh.
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = URL.documentsDirectory.appendingPathComponent("piggyfridge-unreadable-\(stamp).json")
        try? data.write(to: backup, options: .atomic)
        return nil
    }

    private static func loadPresets() -> [FoodPreset] {
        guard let url = Bundle.main.url(forResource: "FoodPresets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let presets = try? JSONDecoder().decode([FoodPreset].self, from: data) else { return [] }
        return presets
    }

    // MARK: - Sample data (Debug builds, and Profile > Developer)

    func clearAll() {
        items = []
        history = []
        inbox = []
        hasSeenCoachTip = false
        hasAskedReminders = false
        userName = ""
        hasAskedName = false
        changed()
    }

    func loadSampleData() {
        func item(_ name: String, _ icon: String, _ category: String, days: Int, _ type: DateType,
                  _ storage: Storage = .fridge, added: Int = -4, kg: Double, gbp: Double, co2: Double) -> FoodItem {
            FoodItem(name: name, iconAsset: icon, category: category, expiry: PFDate.addingDays(days), dateType: type,
                     storage: storage, addedOn: PFDate.addingDays(added), weightKg: kg, priceGBP: gbp, co2eKg: co2)
        }
        items = [
            item("Chicken thighs", "food_chicken_breasts", "Meat", days: -1, .useBy, kg: 0.5, gbp: 2.9, co2: 4.9),
            item("Sliced Bread", "food_sliced_bread", "Bakery", days: -1, .bestBefore, .cupboard, kg: 0.8, gbp: 1.4, co2: 1.3),
            item("Chicken Thighs 1kg", "food_chicken_breasts", "Meat", days: 0, .useBy, kg: 1.0, gbp: 4.5, co2: 9.9),
            item("Baby spinach 500g", "food_baby_spinach", "Veg & salad", days: 0, .useBy, kg: 0.5, gbp: 2.0, co2: 0.7),
            item("Whole Milk 4 Pints", "food_milk", "Dairy & eggs", days: 1, .useBy, kg: 2.34, gbp: 1.65, co2: 7.4),
            item("Scottish Salmon Fillets 240g", "food_salmon_fillets", "Fish", days: 3, .useBy, kg: 0.24, gbp: 3.75, co2: 3.2),
            item("Salted Butter 250g", "food_butter", "Dairy & eggs", days: 3, .bestBefore, kg: 0.25, gbp: 2.1, co2: 5.9),
            item("Tuna Steaks 2 Pack", "food_cod_fillets", "Fish", days: 6, .useBy, kg: 0.24, gbp: 3.5, co2: 1.5),
            item("Mature Cheddar 400g", "food_cheddar_cheese", "Dairy & eggs", days: 8, .bestBefore, added: -4, kg: 0.4, gbp: 3.2, co2: 9.5)
        ]

        func record(_ name: String, _ icon: String, _ outcome: Outcome, daysAgo: Int, hour: Int, minute: Int,
                    _ type: DateType = .useBy, gbp: Double, kg: Double, co2: Double) -> HistoryRecord {
            let day = PFDate.addingDays(-daysAgo)
            let marked = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            let food = FoodItem(name: name, iconAsset: icon, category: "", expiry: PFDate.addingDays(-daysAgo - 1),
                                dateType: type, storage: .fridge, addedOn: PFDate.addingDays(-daysAgo - 5),
                                weightKg: kg, priceGBP: gbp, co2eKg: co2)
            return HistoryRecord(item: food, outcome: outcome, markedAt: marked)
        }
        history = [
            record("Whole Milk 4 Pints", "food_milk", .eaten, daysAgo: 0, hour: 8, minute: 15, gbp: 1.65, kg: 2.34, co2: 7.4),
            record("Chicken breasts", "food_chicken_breasts", .frozen, daysAgo: 0, hour: 7, minute: 40, gbp: 3.5, kg: 0.6, co2: 5.9),
            record("Baby spinach 200g", "food_baby_spinach", .thrown, daysAgo: 1, hour: 20, minute: 40, gbp: 1.2, kg: 0.2, co2: 0.3),
            record("Greek yoghurt", "food_greek_yoghurt", .eaten, daysAgo: 1, hour: 9, minute: 5, .bestBefore, gbp: 1.5, kg: 0.5, co2: 1.6),
            record("Sourdough loaf", "food_sourdough", .eaten, daysAgo: 3, hour: 18, minute: 20, .bestBefore, gbp: 2.2, kg: 0.8, co2: 1.3),
            record("Free range eggs", "food_eggs", .eaten, daysAgo: 3, hour: 10, minute: 10, .bestBefore, gbp: 2.0, kg: 0.36, co2: 1.7),
            record("Mixed salad bag", "food_mixed_salad_bag", .thrown, daysAgo: 3, hour: 19, minute: 55, gbp: 1.0, kg: 0.12, co2: 0.2)
        ]

        let thighs = items[2]
        inbox = [
            InboxMessage(title: "Chicken Thighs 1kg", body: "Its Use By date is today. Cook it tonight or freeze it to keep it safe to eat.",
                         date: Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: .now) ?? .now, dateType: .useBy, itemID: thighs.id),
            InboxMessage(title: "Baby spinach 500g", body: "Its Use By date is today. Have it for lunch.",
                         date: Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: .now) ?? .now, dateType: .useBy, itemID: items[3].id),
            InboxMessage(title: "Tomorrow: Whole Milk 4 Pints", body: "Use By date is tomorrow. Plan it into breakfast.",
                         date: Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: .now) ?? .now, dateType: .useBy, itemID: items[4].id),
            InboxMessage(title: "Your week ahead", body: "6 items reach their date this week. Tap to see them on the calendar.",
                         date: PFDate.addingDays(-2), isRead: true),
            InboxMessage(title: "Reminders are on", body: "We’ll nudge you at 8:30am the day before and on the day a Use By date is due.",
                         date: PFDate.addingDays(-4), isRead: true)
        ]
        hasSeenCoachTip = true
        hasAskedReminders = false
        changed()
    }
}
