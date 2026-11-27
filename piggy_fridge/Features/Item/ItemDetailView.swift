import Foundation
import SwiftUI
import UIKit

/// Food detail: big pixel icon, date info, and what happened to it (eaten / frozen / thrown away / delete).
struct ItemDetailView: View {
    let itemID: UUID

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let item = store.item(with: itemID) {
                content(item)
            } else {
                ContentUnavailableView("This food is no longer in My Food", systemImage: "refrigerator")
            }
        }
        .pfTopBar("", trailing: {
            if store.item(with: itemID) != nil {
                Button("Edit") { showEdit = true }
            }
        })
        .sheet(isPresented: $showEdit) {
            if let item = store.item(with: itemID) {
                EditItemView(item: item)
            }
        }
    }

    private func content(_ item: FoodItem) -> some View {
        let days = PFDate.daysLeft(until: item.expiry)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FoodIconView(asset: item.iconAsset, size: 170, framed: false)
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .background(Palette.surface)

                VStack(alignment: .leading, spacing: 10) {
                    DateTypeBadge(type: item.dateType, overdue: days < 0 && item.dateType == .useBy)
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name).font(.title2.weight(.bold))
                        Spacer()
                        Text(PFDate.relativeLabel(daysLeft: days))
                            .font(.headline)
                            .foregroundStyle(days < 0 ? Palette.danger : Palette.ink)
                    }
                }
                .padding(20)

                Rectangle().fill(Palette.surface).frame(height: 10)

                VStack(spacing: 0) {
                    InfoRow(label: "Category", value: item.category)
                    Divider()
                    InfoRow(label: "Expiry Date", value: PFDate.longDay.string(from: item.expiry))
                    Divider()
                    InfoRow(label: "Date Type", value: item.dateType.sentenceTitle)
                    Divider()
                    InfoRow(label: "Storage", value: item.storage.title)
                    Divider()
                    if let opened = item.openedOn {
                        InfoRow(label: "Opened on", value: PFDate.longDay.string(from: opened))
                        Divider()
                        if let printed = item.printedExpiry, printed != item.expiry {
                            InfoRow(label: "Printed date", value: PFDate.longDay.string(from: printed))
                            Divider()
                        }
                    } else if let rule = store.openedRule(for: item) {
                        InfoRow(label: "After opening", value: rule.hint)
                        Divider()
                    }
                    InfoRow(label: "Added on", value: PFDate.longDay.string(from: item.addedOn))
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button("Mark as eaten") { mark(item, .eaten) }
                    .buttonStyle(PrimaryButtonStyle())
                if item.openedOn == nil, item.storage != .freezer, let rule = store.openedRule(for: item) {
                    Button("I opened it") { open(item, rule) }
                    .buttonStyle(SecondaryButtonStyle())
                }
                HStack(spacing: 10) {
                    if item.storage != .freezer {
                        Button { mark(item, .frozen) } label: { Label("Frozen", systemImage: "snowflake") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button { mark(item, .thrown) } label: { Label("Thrown away", systemImage: "trash") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button("Delete", role: .destructive) { confirmDelete = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)   // bigger tap area
                    .contentShape(Rectangle())
                    .padding(.top, 4)
                    .padding(.bottom, 12)                       // lifts the buttons above off the bottom edge
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .background(Color(.systemBackground))
        }
        .alert("Delete \(item.name)?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { delete(item) }
        } message: {
            Text("It won't be added to your history.")
        }
    }

    private func mark(_ item: FoodItem, _ outcome: Outcome) {
        store.mark(item.id, as: outcome)
        dismiss()
        let verb: String
        switch outcome {
        case .eaten: verb = "marked as eaten"
        case .frozen: verb = "moved to Freezer · 3 months"
        case .thrown: verb = "marked as thrown away"
        }
        toasts.show("\(item.name)\n\(verb)", actionTitle: "Undo") { store.undoLastRemoval() }
    }

    private func open(_ item: FoodItem, _ rule: OpenedRule) {
        guard let before = store.markOpened(item.id) else { return }
        // 보관 장소가 바뀌면 알림에 "Moved to Fridge"를 보여줘요
        let message = rule.storage != item.storage
            ? "Moved to \(rule.storage.title) · \(rule.hint)"
            : "opened · \(rule.hint)"
        toasts.show("\(item.name)\n\(message)", actionTitle: "Undo") { store.update(before) }
    }

    private func delete(_ item: FoodItem) {
        store.delete(item.id)
        dismiss()
        toasts.show("\(item.name)\ndeleted", actionTitle: "Undo") { store.undoLastRemoval() }
    }
}

/// Edit sheet (Figma "Edit Item").
struct EditItemView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FoodItem
    @State private var showIconPicker = false
    @State private var pickedIcon = false
    private let originalName: String

    init(item: FoodItem) {
        _draft = State(initialValue: item)
        originalName = item.name
    }

    var body: some View {
        NavigationStack {
            Form {
                // 아이콘: 누르면 직접 고르기
                Section {
                    HStack {
                        Spacer()
                        Button { showIconPicker = true } label: {
                            VStack(spacing: 8) {
                                FoodIconView(asset: draft.iconAsset, size: 88, framed: false)
                                Text("Tap to change icon")
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)

                Section("Product Name") {
                    TextField("Food name", text: $draft.name)
                }
                Section {
                    DatePicker("Expiry Date", selection: $draft.expiry, displayedComponents: .date)
                    DatePicker("Added on", selection: $draft.addedOn, displayedComponents: .date)
                }
                Section("Date Type") {
                    Picker("Date Type", selection: $draft.dateType) {
                        ForEach(DateType.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                Section {
                    Picker("Storage", selection: $draft.storage) {
                        ForEach(Storage.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .pfTopBar("Edit Item", leading: .close, trailing: {
                Button("Save") {
                    var saved = draft
                    saved.name = saved.name.trimmingCharacters(in: .whitespaces)
                    if saved.name != originalName {
                        // Renamed: category, weight, price and CO2 follow the new food.
                        // The picture follows too, unless an icon was picked by hand.
                        let fresh = store.makeItem(from: AddFoodDraft(name: saved.name))
                        if !pickedIcon { saved.iconAsset = fresh.iconAsset }
                        saved.category = fresh.category
                        saved.weightKg = fresh.weightKg
                        saved.priceGBP = fresh.priceGBP
                        saved.co2eKg = fresh.co2eKg
                    }
                    store.update(saved)
                    dismiss()
                    toasts.show("Changes saved")
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            })
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selected: draft.iconAsset) { picked in
                    draft.iconAsset = picked
                    pickedIcon = true
                }
                .environment(store)
            }
        }
    }
}
