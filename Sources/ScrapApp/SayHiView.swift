import AppKit
import ScrapCore
import SwiftUI

/// Optional first-launch card: a hello, the key shortcuts, and room for an email and suggestions.
/// Nothing leaves the Mac yet; entries are saved locally and the screen says so.
struct SayHiView: View {
    @ObservedObject var model: EditorModel
    let theme: Theme

    @Local private var name = ""
    @Local private var email = ""
    @Local private var message = ""
    @Local private var emailError = false
    @Local private var thanks = false
    @FocusState private var focused: Field?
    private enum Field { case name, email, message }

    private var accent: Color { Color(nsColor: NSColor(hex: theme.accent)) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).onTapGesture { skip() }
            ScrollView {
                card.padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = .name } }
        .onKeyPress(.escape) { skip(); return .handled }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thanks ? "Thanks, saved." : "Welcome to scrap").font(.headline)
                    Text("A free scratchpad in your menu bar.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if thanks {
                Text("Your note is saved on this Mac. Nothing was sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("⌃⌥Space show or hide · ⌘K switch pad · ⌘1–9 jump · gear for settings")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Divider()
                TextField("Name (optional)", text: $name).focused($focused, equals: .name)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Email (optional)", text: $email)
                        .focused($focused, equals: .email)
                        .onChange(of: email) { emailError = false }
                    if emailError { Text("That doesn't look like an email address.").font(.caption).foregroundStyle(.red) }
                }
                TextField("What would make scrap better?", text: $message, axis: .vertical)
                    .focused($focused, equals: .message)
                    .lineLimit(2...4)
                Text("All optional. Nothing is sent anywhere yet: this is saved only on this Mac, and I'll ask again before anything is ever shared.")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text("Or in public:").font(.system(size: 11)).foregroundStyle(.secondary)
                    link("Say hi", "https://github.com/Anubhavdxt/scrap/discussions/new?category=general&title=Hi%20from%20a%20scrap%20user")
                    link("Share an idea", "https://github.com/Anubhavdxt/scrap/discussions/new?category=ideas")
                    link("★ Star", "https://github.com/Anubhavdxt/scrap")
                }
                HStack {
                    Button("Skip") { skip() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Say hi") { submit() }.keyboardShortcut(.defaultAction).tint(accent)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(16)
        .frame(maxWidth: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 14)
    }

    private func link(_ title: String, _ url: String) -> some View {
        Button(title) {
            model.finishSayHi(nil)
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        }
        .buttonStyle(.link)
        .font(.system(size: 11))
    }

    private func skip() { model.finishSayHi(nil) }

    private func submit() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !EmailValidator.isValid(trimmed) {
            emailError = true
            focused = .email
            return
        }
        let entry = HelloEntry(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: trimmed,
                               message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        if entry.isEmpty { return skip() }
        withAnimation { thanks = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { model.finishSayHi(entry) }
    }
}
