import Foundation
import SwiftUI
import UIKit

struct AccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @State private var confirmLogOut = false

    var body: some View {
        if let account = store.account {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text(String(account.name.prefix(1)).uppercased())
                            .font(.title2.weight(.bold))
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Palette.yellow))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name).font(.headline)
                            Text(account.email).font(.footnote).foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Details") {
                    NavigationLink(value: ProfileRoute.editName) {
                        LabeledContent("Name", value: account.name)
                    }
                    LabeledContent("Email", value: account.email)
                    if account.method == .email {
                        NavigationLink(value: ProfileRoute.changePassword) {
                            LabeledContent("Password", value: "Change")
                        }
                    }
                    LabeledContent("Signed in with", value: account.method.title)
                }
                Section("Your data") {
                    if let url = store.exportData() {
                        ShareLink(item: url) {
                            Label("Download my data", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                Section {
                    Button("Log out") { confirmLogOut = true }
                        .foregroundStyle(Palette.ink)
                    NavigationLink(value: ProfileRoute.deleteAccount) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete account").foregroundStyle(Palette.danger)
                            Text("Permanently delete your account, food list and history.")
                                .font(.caption).foregroundStyle(Palette.inkTertiary)
                        }
                    }
                }
            }
            .pfTopBar("Account")
            .alert("Log out?", isPresented: $confirmLogOut) {
                Button("Cancel", role: .cancel) {}
                Button("Log out", role: .destructive) {
                    store.signOut()
                    router.profilePath = []
                    toasts.show("Logged out")
                }
            } message: {
                Text("Your food list stays on this iPhone. Sign in again any time with your email and password.")
            }
        } else {
            ContentUnavailableView("Signed out", systemImage: "person.crop.circle")
        }
    }
}

struct EditNameView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What should we call you?").font(.title2.weight(.bold))
                Text("We use your first name to greet you in the app.").font(.subheadline).foregroundStyle(Palette.inkSecondary)
            }
            LabeledField(label: "First name") {
                TextField("First name", text: $name).textContentType(.givenName)
            }
            Spacer()
            Button("Save") {
                store.setUserName(name)
                dismiss()
                toasts.show("Name updated")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(20)
        .pfTopBar("Name")
        .onAppear { name = store.userName }
    }
}

struct ChangePasswordView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var showErrors = false
    @State private var currentWrong = false

    private var currentError: String? { showErrors && (current.count < 8 || currentWrong) ? "That password isn’t right. Try again." : nil }
    private var newError: String? {
        guard showErrors else { return nil }
        if new.count < 8 { return "Use at least 8 characters" }
        if new == current { return "Choose a password different from your current one" }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Change your password").font(.title2.weight(.bold))
                    Text("Enter your current password, then choose a new one.").font(.subheadline).foregroundStyle(Palette.inkSecondary)
                }
                LabeledField(label: "Current password", error: currentError) {
                    PasswordField(placeholder: "Current password", text: $current)
                }
                LabeledField(label: "New password", error: newError) {
                    PasswordField(placeholder: "New password", text: $new)
                }
                if newError == nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("At least 8 characters", systemImage: new.count >= 8 ? "checkmark.circle.fill" : "circle")
                        Label("Different from your current password",
                              systemImage: !new.isEmpty && new != current ? "checkmark.circle.fill" : "circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(20)
        }
        .pfTopBar("Password")
        .safeAreaInset(edge: .bottom) {
            Button("Update password") {
                showErrors = true
                currentWrong = !Credentials.verify(password: current, email: store.account?.email ?? "")
                guard currentError == nil, newError == nil else { return }
                Credentials.save(password: new, email: store.account?.email ?? "")
                dismiss()
                toasts.show("Password updated")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }
}

struct DeleteAccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = false
    @State private var wrongPassword = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Delete your account?").font(.title2.weight(.bold))
                    Text("This permanently deletes your account and everything in it. You can’t undo this.")
                        .font(.subheadline).foregroundStyle(Palette.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("What will be deleted").font(.subheadline.weight(.semibold))
                    Text("Your food list (\(store.items.count) items)")
                    Text("Your history and savings summary")
                    Text("Your reminder settings")
                }
                .font(.subheadline)
                .pfCard()
                if store.account?.method == .email {
                    LabeledField(label: "Enter your password to confirm", error: wrongPassword ? "That password isn’t right. Try again." : nil) {
                        PasswordField(placeholder: "Password", text: $password)
                            .onChange(of: password) { _, _ in wrongPassword = false }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Just want fewer notifications?").foregroundStyle(Palette.inkSecondary)
                    NavigationLink("Change reminder settings", value: ProfileRoute.notificationSettings)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                }
                .font(.footnote)
            }
            .padding(20)
        }
        .pfTopBar("Delete account")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button("Delete account") {
                    if store.account?.method == .email,
                       !Credentials.verify(password: password, email: store.account?.email ?? "") {
                        wrongPassword = true
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        return
                    }
                    confirm = true
                }
                    .buttonStyle(PrimaryButtonStyle(background: Palette.danger))
                    .disabled(store.account?.method == .email && password.count < 8)
                Button("Keep my account") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .alert("Delete your account?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.deleteAccount()
                UserDefaults.standard.set(false, forKey: "hasSeenSignUp")   // 회원가입 화면 다시 보이게
                router.profilePath = [.accountDeleted]
            }
        } message: {
            Text("Your food list, history and settings will be deleted for good.")
        }
    }
}

struct AccountDeletedView: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold))
                .frame(width: 96, height: 96)
                .background(Circle().fill(Palette.surface))
            Text("Your account has been deleted").font(.title2.weight(.bold)).multilineTextAlignment(.center)
            Text("Thanks for using Piggy Fridge. Your data will be fully removed from our servers within 30 days.")
                .font(.subheadline).foregroundStyle(Palette.inkSecondary).multilineTextAlignment(.center)
            Spacer()
            Button("Done") {
                          router.goHome()
                          router.showOnboarding = true   // 바로 회원가입 화면 띄우기
                      }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }
}


/// Asked once, right after the splash on a fresh install. Skip is fine: the greeting just says "Welcome".
struct NameSetupSheet: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What should we call you?").font(.title2.weight(.bold))
                Text("Your first name is only used to greet you. It stays on this iPhone.")
                    .font(.subheadline).foregroundStyle(Palette.inkSecondary)
            }
            LabeledField(label: "First name") {
                TextField("First name", text: $name)
                    .textContentType(.givenName)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            Button("Continue", action: save)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Skip for now") { store.setUserName("") }
                .buttonStyle(LinkButtonStyle())
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(24)
        .presentationDetents([.height(380)])
        .presentationCornerRadius(24)
        .interactiveDismissDisabled()
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.setUserName(trimmed)
    }
}
