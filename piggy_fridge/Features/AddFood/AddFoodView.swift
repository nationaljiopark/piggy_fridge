import Foundation
import SwiftUI
import UIKit

/// Figma "Add food": name with quick chips, date type, date with quick chips (plus the food's usual shelf life),
/// errors with a shake, Save and "Save and add another".
struct AddFoodView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var draft: AddFoodDraft
    @State private var showErrors = false
    @State private var shakes: CGFloat = 0
    @State private var showDatePicker = false
    @State private var addedMessage: String?
    @FocusState private var nameFocused: Bool

    private let quickNames = [["Milk", "Eggs", "Chicken breasts", "Bread"], ["Baby spinach", "Yoghurt"]]
    private let quickDays = [QuickDay(label: "Today", days: 0), QuickDay(label: "Tomorrow", days: 1),
                             QuickDay(label: "In 3 days", days: 3), QuickDay(label: "In a week", days: 7)]

    init(draft: AddFoodDraft) {
        _draft = State(initialValue: draft)
    }

    private var nameError: String? {
        showErrors && draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter the name of the food" : nil
    }

    private var dateError: String? {
        showErrors && draft.date == nil ? "Choose the date printed on the label" : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    nameSection
                    dateTypeSection
                    dateSection
                    storageSection
                }
                .padding(20)
                .modifier(Shake(animatableData: shakes))
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                // A typed name that is one of the 100 foods starts with that food's usual storage (Search → Add).
                if draft.date == nil, let preset = store.preset(named: draft.name) { draft.storage = preset.storageBeforeOpening }
            }
            .pfTopBar("Add food", leading: .close)
            .safeAreaInset(edge: .bottom) { actions }
            .overlay(alignment: .bottom) {
                if let addedMessage {
                    HStack {
                        Text(addedMessage).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        Spacer()
                        Button("View list") {
                            dismiss()
                            router.goHome()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.yellow)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(Palette.coach))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 130)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(title: draft.dateType.dateFieldLabel, date: draft.date ?? .now) { picked in
                    draft.date = picked
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(Color(.systemBackground))   // solid white, no see-through glass
                .presentationCornerRadius(24)
                .presentationDragIndicator(.hidden)
            }
        }
    }

    // MARK: Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(label: "Food name", error: nameError) {
                TextField("e.g. Semi-skimmed milk", text: $draft.name)
                    .focused($nameFocused)
                    .submitLabel(.done)
            }
            let suggestions = store.suggestions(for: draft.name).filter { $0.name.lowercased() != draft.name.lowercased() }
            if nameFocused && !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { preset in
                            Button(preset.name) { pick(preset.name) }.buttonStyle(ChipStyle())
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(quickNames, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(row, id: \.self) { name in
                                Button(name) { pick(name) }
                                    .buttonStyle(ChipStyle(isSelected: draft.name == name))
                            }
                        }
                    }
                }
            }
        }
    }

    private var dateTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date on the label").font(.pfLabel)
            HStack(spacing: 8) {
                ForEach(DateType.allCases) { type in
                    Button(type.title) { draft.dateType = type }
                        .buttonStyle(SegmentButtonStyle(isSelected: draft.dateType == type))
                        .accessibilityAddTraits(draft.dateType == type ? .isSelected : [])
                }
            }
            Text(draft.dateType.helper)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(label: draft.dateType.dateFieldLabel, error: dateError) {
                Button {
                    showDatePicker = true
                } label: {
                    HStack {
                        Text(draft.date.map { PFDate.fieldLabel(for: $0) } ?? "Choose a date")
                            .foregroundStyle(draft.date == nil ? Palette.inkTertiary : Palette.ink)
                        Spacer()
                        Image(systemName: "calendar").foregroundStyle(Palette.ink)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            // Chips wrap onto the next line instead of squashing ("Tomorrow" no longer breaks in two).
            PFFlowLayout(spacing: 8) {
                // Food from the 100 list (bananas, bread…) often has no date on it,
                // so offer its usual shelf life as a suggestion. Tapping it fills the date; nothing is filled silently.
                if let typical = typicalDays {
                    let date = PFDate.addingDays(typical)
                    let selected = draft.date.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
                    Button("Usually \(Self.spanLabel(typical))") { draft.date = date }
                        .buttonStyle(ChipStyle(isSelected: selected))
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHint("Sets the date to when this food usually goes off")
                }
                ForEach(quickDays) { quick in
                    let date = PFDate.addingDays(quick.days)
                    let selected = draft.date.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
                    Button(quick.label) { draft.date = date }
                        .buttonStyle(ChipStyle(isSelected: selected))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }

    /// Usual shelf life of the typed food, when it is one of the 100 foods (and not one of the quick chips already).
    private var typicalDays: Int? {
        guard let preset = store.preset(named: draft.name.trimmingCharacters(in: .whitespaces)),
              preset.typicalDays > 0,
              !quickDays.contains(where: { $0.days == preset.typicalDays }) else { return nil }
        return preset.typicalDays
    }

    /// 5 → "5 days", 14 → "2 weeks", 90 → "3 months", 365 → "1 year"
    static func spanLabel(_ days: Int) -> String {
        if days >= 365, days % 365 == 0 { return days == 365 ? "1 year" : "\(days / 365) years" }
        if days >= 60 { let m = Int((Double(days) / 30).rounded()); return "\(m) months" }
        if days >= 14, days % 7 == 0 { return "\(days / 7) weeks" }
        return days == 1 ? "1 day" : "\(days) days"
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where do you keep it?").font(.pfLabel)
            HStack(spacing: 8) {
                ForEach(Storage.allCases) { place in
                    Button(place.title) { draft.storage = place }
                        .buttonStyle(SegmentButtonStyle(isSelected: draft.storage == place))
                        .accessibilityAddTraits(draft.storage == place ? .isSelected : [])
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 14) {
            Button("Save") { save(addAnother: false) }
                .buttonStyle(PrimaryButtonStyle())
            Button("Save and add another") { save(addAnother: true) }
                .buttonStyle(LinkButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    // MARK: Logic

    private func pick(_ name: String) {
        draft.name = name
        nameFocused = false
        if let preset = store.preset(named: name) {
            draft.dateType = preset.dateType == .notSure ? .bestBefore : preset.dateType
            draft.storage = preset.storageBeforeOpening
        }
    }

    private func save(addAnother: Bool) {
        let isValid = !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draft.date != nil
        guard isValid else {
            showErrors = true
            withAnimation(.linear(duration: 0.35)) { shakes += 1 }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let item = store.makeItem(from: draft)
        store.add(item)

        if addAnother {
            showErrors = false
            draft = AddFoodDraft()
            withAnimation(.snappy) { addedMessage = "\(item.name) added" }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.snappy) { addedMessage = nil }
            }
        } else {
            dismiss()
            router.goHome()
            if !store.hasAskedReminders {
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    router.showReminderPrompt = true
                }
            } else {
                toasts.show("\(item.name)\nadded to My Food")
            }
        }
    }
}

/// Lays chips out left to right and wraps to a new line when the row is full.
/// Each chip keeps its natural width, so its text never breaks in two.
struct PFFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct QuickDay: Identifiable {
    let label: String
    let days: Int
    var id: String { label }
}

/// Graphical date picker in a sheet (Figma "Overlay / Sheet — Expiry date").
struct DatePickerSheet: View {
    let title: String
    @State var date: Date
    var onConfirm: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                .pfTopBar(title, leading: .close, trailing: {
                    Button { onConfirm(date); dismiss() } label: { PFCheckIcon() }
                        .accessibilityLabel("Done")
                })
                // Space above the title bar, so it does not touch the top edge of the sheet.
                .safeAreaInset(edge: .top, spacing: 0) { Color(.systemBackground).frame(height: 16) }
                .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
    }
}
