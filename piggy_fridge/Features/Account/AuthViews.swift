import Foundation
import SwiftUI
import UIKit

// Sign in / Sign up are local mocks for now: they store a name and email on the phone.
// Next step: Sign in with Apple (AuthenticationServices) and a backend for real backups.

struct SignInView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @State private var email = ""
    @State private var password = ""
    @State private var showErrors = false
    @State private var wrongLogin = false

    private var emailError: String? {
        showErrors && !Validation.isEmail(email) ? "Enter an email address like name@example.com" : nil
    }
    private var passwordError: String? {
        if showErrors && password.count < 8 { return "Use at least 8 characters" }
        if wrongLogin { return "That email or password isn’t right. Try again." }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome back").font(.title.weight(.bold))
                    Text("Sign in with the email and password you created on this iPhone.").font(.subheadline).foregroundStyle(Palette.inkSecondary)
                }
                LabeledField(label: "Email", error: emailError) {
                    TextField("name@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledField(label: "Password", error: passwordError) {
                    PasswordField(placeholder: "Your password", text: $password)
                }
                NavigationLink("Forgot password?", value: ProfileRoute.resetLinkSent(email.isEmpty ? "your email" : email))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Button("Sign in") {
                    showErrors = true
                    wrongLogin = false
                    guard emailError == nil, passwordError == nil else { return }
                    guard Credentials.verify(password: password, email: email) else { wrongLogin = true; return }
                    let name = store.account.flatMap { $0.email.lowercased() == email.lowercased() ? $0.name : nil }
                        ?? (email.split(separator: "@").first.map { String($0).capitalized } ?? "Friend")
                    finish(name: name, email: email, method: .email)
                }
                .buttonStyle(PrimaryButtonStyle())
                HStack(spacing: 4) {
                    Text("New to Piggy Fridge?").foregroundStyle(Palette.inkSecondary)
                    NavigationLink("Create account", value: ProfileRoute.signUp)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                
            }
            .padding(20)
        }
        .pfTopBar("Sign in")
    }

    private func finish(name: String, email: String, method: SignInMethod) {
        store.signIn(name: name, email: email, method: method)
        router.profilePath = []
        router.showOnboarding = false
        toasts.show("Signed in as \(name)")
    }
}

struct SignUpView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if router.showOnboarding {
            // 첫 실행: 뒤로 가기(<) 없음
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content.pfTopBar("")
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Save your food list").font(.title.weight(.bold))
                    Text("Create a free Piggy Fridge account. Your account and food list are stored on this iPhone.")
                        .font(.subheadline).foregroundStyle(Palette.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    benefit("Keep your food and dates in one place")
                    benefit("Keep your reminder settings")
                    benefit("Delete everything any time from Account")
                }
                NavigationLink(value: ProfileRoute.signUpEmail) {
                    Text("Sign up with email")
                }
                .buttonStyle(SecondaryButtonStyle())
                HStack(spacing: 4) {
                    Text("Already have an account?").foregroundStyle(Palette.inkSecondary)
                    NavigationLink("Log in", value: ProfileRoute.signIn)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                // 첫 실행 때만 Guest 버튼
                if router.showOnboarding {
                    Button {
                        router.goHome()
                    } label: {
                        Text("Continue as guest")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                LegalConsentText()
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Palette.surface))
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
struct SignUpEmailView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var tips = false
    @State private var showErrors = false
    @State private var emailTaken = false

    private var nameError: String? { showErrors && name.trimmingCharacters(in: .whitespaces).isEmpty ? "Enter your first name" : nil }
    private var emailError: String? {
        if showErrors && !Validation.isEmail(email) { return "Enter an email address like name@example.com" }
        if emailTaken { return "This email already has an account on this iPhone. Log in instead." }
        return nil
    }
    private var passwordError: String? { showErrors && password.count < 8 ? "Use at least 8 characters" : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sign up with email").font(.title.weight(.bold))
                LabeledField(label: "First name", error: nameError) {
                    TextField("e.g. Sam", text: $name).textContentType(.givenName)
                }
                LabeledField(label: "Email", error: emailError) {
                    TextField("name@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                VStack(alignment: .leading, spacing: 6) {
                    LabeledField(label: "Password", error: passwordError) {
                        PasswordField(placeholder: "Create a password", text: $password)
                    }
                    if passwordError == nil {
                        Text("At least 8 characters").font(.footnote).foregroundStyle(Palette.inkTertiary)
                    }
                }
                Label("Your account and food list are stored on this iPhone. Your password is kept in the iPhone Keychain, never as plain text.",
                      systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                LegalConsentText(prefix: "By creating an account, you agree to our")
            }
            .padding(20)
        }
        .pfTopBar("")
        .safeAreaInset(edge: .bottom) {
            Button("Create account") {
                showErrors = true
                emailTaken = Validation.isEmail(email) && Credentials.exists(email: email)
                guard nameError == nil, emailError == nil, passwordError == nil else { return }
                Credentials.save(password: password, email: email)
                store.signIn(name: name.trimmingCharacters(in: .whitespaces), email: email, method: .email)
                router.profilePath.append(.accountReady)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }
}

struct AccountReadyView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 96, height: 96)
                .background(Circle().fill(Palette.yellow))
                .frame(maxWidth: .infinity)
            VStack(spacing: 8) {
                Text("Your account is ready").font(.title.weight(.bold))
                Text("You can start adding food right away. Everything is saved on this iPhone.")
                    .font(.subheadline).foregroundStyle(Palette.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            VStack(spacing: 0) {
                statusRow("iphone", "Your food is saved on this iPhone", "Everything you add stays on your phone")
                Divider().padding(.leading, 64)
                statusRow("bell.fill", "Never miss an expiry date", "Turn on reminders to get notified before food expires.")
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
            Spacer()
            Button("Get started") { router.goHome() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func statusRow(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.footnote).foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

struct ResetLinkSentView: View {
    let email: String
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "envelope")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: 96, height: 96)
                .background(Circle().fill(Palette.yellow))
            Text("Password reset").font(.title.weight(.bold))
            Text("Your account lives only on this iPhone, so we can’t email a reset link. If you remember your old password, change it in Account. If not, delete the app to remove the account, then create a new one.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Back to sign in") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .pfTopBar("")
    }
}

/// Apple and Google buttons (mock sign-in for now).
struct SocialButtons: View {
    var onSignIn: (SignInMethod) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button { onSignIn(.apple) } label: {
                Label("Continue with Apple", systemImage: "apple.logo")
            }
            .buttonStyle(PrimaryButtonStyle(background: .black))

            Button { onSignIn(.google) } label: {
                HStack(spacing: 8) {
                    Text("G").font(.headline.weight(.bold))
                    Text("Continue with Google")
                }
            }
            .buttonStyle(OutlineButtonStyle())
        }
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.fieldBorder, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct OrDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Palette.fieldBorder).frame(height: 1)
            Text("or").font(.footnote).foregroundStyle(Palette.inkTertiary)
            Rectangle().fill(Palette.fieldBorder).frame(height: 1)
        }
    }
}

enum Validation {
    static func isEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty && !parts[1].hasSuffix(".")
    }
}
