import Foundation
import SwiftUI
import UIKit

/// Search My Food. Results keep the Home grouping; no results offers to add the food.
struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                let results = store.search(trimmed)
                if trimmed.isEmpty {
                    hint
                } else if results.isEmpty {
                    noResults(trimmed)
                } else {
                    resultsList(results)
                }
            }
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                if case .item(let id) = route { ItemDetailView(itemID: id) }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(350))
                fieldFocused = true
            }
        }
    }

    /// Search field in the same style as the other text fields in the app (white, thin border), not the system glass bar.
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.inkTertiary)
                TextField("Search My Food", text: $query)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { fieldFocused = false }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.chartGray)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.fieldBorder, lineWidth: 1))

            Button("Cancel") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var hint: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Search by food name, like “milk” or “chicken”.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func resultsList(_ results: [FoodItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("\(results.count) result\(results.count == 1 ? "" : "s") in My Food")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.inkTertiary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                ForEach(FoodSection.allCases) { section in
                    let items = results.filter { FoodSection.section(for: $0) == section }
                    if !items.isEmpty {
                        SectionHeaderRow(title: section.title, count: items.count, note: section.note, alert: section == .dontEat)
                        ForEach(items) { item in
                            NavigationLink(value: HomeRoute.item(item.id)) { FoodCardRow(item: item).id(item.hashValue) }
                                .buttonStyle(.plain)
                        }
                        Spacer().frame(height: 16)
                    }
                }
            }
        }
    }

    private func noResults(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(Palette.inkTertiary)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Palette.surface))
            Text("No results for “\(text)”").font(.headline)
            Text("It isn’t in My Food yet. Add it now and we’ll remind you before it goes off.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Add \(text)") {
                let draft = AddFoodDraft(name: text.prefix(1).uppercased() + text.dropFirst())
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    router.startAddFood(draft)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.top, 96)
    }
}
