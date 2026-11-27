import Foundation
import SwiftUI
import UIKit

/// The bell: reminders that were sent, grouped into Today and Earlier this week.
struct InboxView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts

    private var today: [InboxMessage] {
        store.inbox.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date > $1.date }
    }

    private var earlier: [InboxMessage] {
        store.inbox.filter { !Calendar.current.isDateInToday($0.date) }.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            if store.inbox.isEmpty {
                ContentUnavailableView("No notifications yet", systemImage: "bell",
                                       description: Text("We’ll let you know here when food is close to its date."))
                    .listRowSeparator(.hidden)
            }
            if !today.isEmpty {
                Section {
                    ForEach(today) { row($0) }
                } header: {
                    HStack {
                        Text("Today")
                        Spacer()
                        if store.unreadCount > 0 {
                            Text("\(store.unreadCount) new")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Palette.yellow))
                        }
                    }
                }
            }
            if !earlier.isEmpty {
                Section("Earlier this week") {
                    ForEach(earlier) { row($0) }
                }
            }
        }
        .listStyle(.plain)
        .pfTopBar("Notifications", trailing: {
            Button("Mark all read") {
                withAnimation(.easeIn(duration: 0.3)) { store.clearInbox() }
                toasts.show("Notifications cleared", actionTitle: "Undo") {
                    withAnimation(.easeIn(duration: 0.3)) { store.undoClearInbox() }
                }
            }
            .disabled(store.inbox.isEmpty)
        })
        // ▼ 추가: 화면을 열 때 읽은 지 14일 지난 알림 정리
        .onAppear { store.removeOldReadMessages() }
        // Once you have looked through the list, the red dot on the bell goes away.
        .onDisappear { store.markAllRead() }
    }

    private func row(_ message: InboxMessage) -> some View {
        Button {
            store.markRead(message.id)
            if let id = message.itemID, store.item(with: id) != nil {
                router.homePath.append(.item(id))
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(message.isRead ? Color.clear : Palette.danger)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(message.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(Calendar.current.isDateInToday(message.date)
                             ? PFDate.time.string(from: message.date)
                             : PFDate.make("EEE").string(from: message.date))
                            .font(.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    Text(message.body)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    if let type = message.dateType {
                        DateTypeBadge(type: type)
                    }
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // ▼ 추가: 왼쪽으로 밀면 Delete / Read
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { store.deleteMessage(message.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            if !message.isRead {
                Button {
                    withAnimation { store.markRead(message.id) }
                } label: {
                    Label("Read", systemImage: "envelope.open")
                }
                .tint(Palette.inkSecondary)
            }
        }
    }
}
