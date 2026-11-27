import Foundation
import SwiftUI
import UIKit

// Privacy Policy and Terms of Use, readable inside the app before sign-up.
// The text describes what this build actually does. Update it (and LegalInfo.version)
// whenever the app starts collecting something new, for example a real sign-in backend.
// Not legal advice: have it checked before the App Store release.

enum LegalInfo {
    static let version = "1.0"
    static let effectiveDate = "31 October 2026"
    static let operatorName = "Noontide Studio"   // [확인 필요] legal name of the operator
    static let contact = Feedback.address
}

private struct LegalSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

private struct LegalDocumentView: View {
    let title: String
    let intro: String
    let sections: [LegalSection]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Version \(LegalInfo.version) · Effective \(LegalInfo.effectiveDate)")
                    .font(.caption)
                    .foregroundStyle(Palette.inkTertiary)
                Text(intro)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title).font(.headline).accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
        }
        .pfTopBar(title)
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        LegalDocumentView(
            title: "Privacy Policy",
            intro: "Piggy Fridge helps you remember when your food expires. We keep as little information as we can, and most of it never leaves your iPhone.",
            sections: [
                LegalSection(title: "What we keep",
                             body: "Your food list (names, dates, storage place, estimated price), your history of what was eaten, frozen or thrown away, and your reminder settings."),
                LegalSection(title: "Where it is stored",
                             body: "On your iPhone only. This version has no server and no backup, so we cannot see your food list. Deleting the app deletes this data."),
                LegalSection(title: "Camera",
                             body: "The camera reads the date and barcode on a label. The picture is read on your iPhone by Apple’s Vision framework. Photos are not saved and are not sent anywhere."),
                LegalSection(title: "Barcode lookup",
                             body: "When the camera reads a barcode, only the barcode number is sent to Open Food Facts (openfoodfacts.org, run by a non-profit in France) to find the product name. Their product data is shared under the Open Database License (ODbL). No name, email or location is sent with it."),
                LegalSection(title: "Notifications",
                             body: "Reminders are scheduled on your iPhone. You can turn them off in My Piggy → Notifications or in iOS Settings."),
                LegalSection(title: "What we don’t do",
                             body: "No ads, no tracking across apps, no analytics tools, and we do not sell or share your information."),
                LegalSection(title: "Children",
                             body: "Piggy Fridge is not made for children under 13 and we do not knowingly collect their information."),
                LegalSection(title: "Your choices",
                             body: "There is no account and no sign-in. You can edit or delete any food item, export a copy of your data, and delete everything in My Piggy → My data → Delete all data. That removes your food list, history and settings from this iPhone straight away."),
                LegalSection(title: "Contact",
                             body: "\(LegalInfo.operatorName) · \(LegalInfo.contact)\nIf you are in the UK you can also contact the Information Commissioner’s Office (ico.org.uk)."),
                LegalSection(title: "Changes",
                             body: "If this policy changes, we will update the version and date above and tell you in the app before the change applies."),
            ])
    }
}

struct TermsView: View {
    var body: some View {
        LegalDocumentView(
            title: "Terms of Use",
            intro: "These terms apply when you use Piggy Fridge. Please read them before you create an account.",
            sections: [
                LegalSection(title: "The service",
                             body: "Piggy Fridge is free. It stores your food list and sends reminders before dates pass. Some features may change as we improve the app."),
                LegalSection(title: "Dates are a guide",
                             body: "The app shows the dates you enter or scan. Scanning can misread a label, so check the date on the pack. Never eat food after its Use by date. Best before dates are about quality: look and smell before you eat."),
                LegalSection(title: "Your data",
                             body: "Everything you add stays on your iPhone. You can stop using the app and delete all your data at any time in My Piggy → My data → Delete all data."),
                LegalSection(title: "Product data",
                             body: "Product names found by barcode come from Open Food Facts (openfoodfacts.org), available under the Open Database License (ODbL). They may be incomplete or wrong, so check the pack."),
                LegalSection(title: "Fair use",
                             body: "Don’t try to break, copy or misuse the app or the barcode lookup."),
                LegalSection(title: "Your rights",
                             body: "Nothing in these terms takes away rights you have under consumer law."),
                LegalSection(title: "Changes and contact",
                             body: "If these terms change, we will update the version and date above and tell you in the app. Questions: \(LegalInfo.contact)"),
            ])
    }
}

/// "By continuing, you agree to our Terms and Privacy Policy." with both names tappable.
struct LegalConsentText: View {
    var prefix: String = "By continuing, you agree to our"
    @Environment(Router.self) private var router

    var body: some View {
        Text(attributed)
            .font(.caption)
            .foregroundStyle(Palette.inkTertiary)
            .tint(Palette.ink)
            .environment(\.openURL, OpenURLAction { url in
                switch url.host {
                case "terms": router.profilePath.append(.terms)
                case "privacy": router.profilePath.append(.privacy)
                default: return .systemAction
                }
                return .handled
            })
    }

    private var attributed: AttributedString {
        var text = AttributedString("\(prefix) ")
        var terms = AttributedString("Terms")
        terms.link = URL(string: "piggyfridge://terms")
        terms.underlineStyle = .single
        var privacy = AttributedString("Privacy Policy")
        privacy.link = URL(string: "piggyfridge://privacy")
        privacy.underlineStyle = .single
        text += terms
        text += AttributedString(" and ")
        text += privacy
        text += AttributedString(".")
        return text
    }
}
