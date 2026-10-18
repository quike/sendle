import SendleDomain
import SwiftUI

/// Amazon's device and approved-senders page.
let amazonContentAndDevicesURL = URL(string: "https://www.amazon.com/mycd")

struct LabeledField<Content: View>: View {
  let label: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.muted)
      content
    }
  }
}

/// `label` is what VoiceOver calls the field; the screen shows its own label above it.
struct GlassTextField: View {
  let label: String
  let prompt: String
  @Binding var text: String
  var isSecure = false

  var body: some View {
    Group {
      if isSecure {
        SecureField(label, text: $text, prompt: Text(prompt).foregroundStyle(Theme.faint))
      } else {
        TextField(label, text: $text, prompt: Text(prompt).foregroundStyle(Theme.faint))
      }
    }
    .labelsHidden()
    .accessibilityLabel(label)
    .textFieldStyle(.plain)
    .font(.system(size: 12))
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .glass(cornerRadius: 11)
  }
}

struct KindleAddressField: View {
  @Bindable var form: EmailForm

  var body: some View {
    LabeledField(label: "Kindle email") {
      GlassTextField(
        label: "Kindle email", prompt: "name@kindle.com", text: $form.kindleAddress)
      if form.issues.contains(.invalidKindleAddress) {
        FieldNote(text: form.message(for: .invalidKindleAddress), color: Theme.danger)
      } else if let warning = form.kindleAddressWarning {
        FieldNote(text: warning, color: Theme.warm)
      }
    }
  }
}

struct ApprovedSendersNote: View {
  let open: (URL) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(
        "Amazon only delivers email from addresses on your approved list. Add the address Sendle "
          + "sends from under Preferences › Personal Document Settings."
      )
      .font(.system(size: 11))
      .foregroundStyle(Color.white.opacity(0.7))
      .fixedSize(horizontal: false, vertical: true)
      if let url = amazonContentAndDevicesURL {
        Button("Open Amazon's settings ↗") { open(url) }
          .buttonStyle(.plain)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Theme.link)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
  }
}

struct SenderFields: View {
  @Bindable var form: EmailForm
  /// The setting a settings search led to.
  var highlighted: SettingsItem?
  let open: (URL) -> Void

  var body: some View {
    let marked = highlighted?.onScreen(for: form.provider)
    VStack(alignment: .leading, spacing: 12) {
      LabeledField(label: "Send with") {
        ProviderTiles(form: form)
        if let server = form.provider.defaultServer {
          FieldNote(text: server.summary, color: Theme.faint)
        }
      }
      .settingsHighlight(marked == .mailProvider)
      LabeledField(label: "Sender address") {
        GlassTextField(
          label: "Sender address", prompt: "you@example.com", text: $form.senderAddress)
        issueNote(.invalidSenderAddress)
      }
      .settingsHighlight(marked == .senderAddress)
      LabeledField(label: "App password") {
        GlassTextField(
          label: "App password", prompt: form.passwordPrompt, text: $form.password,
          isSecure: true)
        issueNote(.missingPassword)
        FieldNote(text: form.appPasswordHelp)
        if let link = form.appPasswordLink {
          Button("Create one ↗") { open(link) }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Theme.link)
        }
      }
      .settingsHighlight(marked == .appPassword)
      if form.provider == .custom {
        LabeledField(label: "Mail server") {
          HStack(spacing: 6) {
            GlassTextField(label: "Mail server", prompt: "smtp.example.com", text: $form.customHost)
            GlassTextField(label: "Port", prompt: "Port", text: $form.customPort).frame(width: 64)
          }
          Picker("Security", selection: $form.customSecurity) {
            Text("TLS").tag(SMTPSecurity.implicitTLS)
            Text("STARTTLS").tag(SMTPSecurity.startTLS)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          issueNote(.missingServer)
        }
        .settingsHighlight(marked == .mailServer)
      }
    }
  }

  @ViewBuilder
  private func issueNote(_ issue: EmailSetupIssue) -> some View {
    if form.issues.contains(issue) {
      FieldNote(text: form.message(for: issue), color: Theme.danger)
    }
  }
}

/// One tile per mail provider, in its brand's colour with a glyph Sendle draws: no company logos.
struct ProviderTiles: View {
  @Bindable var form: EmailForm

  var body: some View {
    HStack(spacing: 6) {
      ForEach(MailProvider.allCases, id: \.self) { provider in
        let isOn = form.provider == provider
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button {
          form.provider = provider
        } label: {
          VStack(spacing: 5) {
            Image(systemName: provider.symbol)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 24, height: 24)
              .background(
                LinearGradient(
                  colors: provider.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(provider.pickerName)
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(isOn ? Theme.text : Theme.muted)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .background(isOn ? Theme.accent.opacity(0.16) : Theme.glass, in: shape)
          .overlay(shape.strokeBorder(isOn ? Theme.accent.opacity(0.6) : Theme.line))
          .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(provider.pickerName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
      }
    }
  }
}

/// "Send test" proves the login, the server and Amazon's approved senders in one go.
struct SendTestRow: View {
  let form: EmailForm
  /// Opens the logs at a failed test, while logs are on.
  var showLogs: (() -> Void)?
  let send: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Button("Send test", action: send)
          .buttonStyle(SecondaryButtonStyle())
          .disabled(form.isSaving || form.testStatus == .sending)
        if form.testStatus == .sending {
          ProgressView().controlSize(.small)
        } else {
          FieldNote(text: form.testHint, color: Theme.faint)
        }
      }
      switch form.testStatus {
      case .sent(let text):
        FieldNote(text: text, color: Theme.live)
      case .failed(let problem):
        FieldNote(
          text: [problem.title, problem.message].compactMap { $0 }.joined(separator: ". "),
          color: Theme.danger)
        if let showLogs { ShowLogsLink(open: showLogs) }
      case .idle, .sending:
        EmptyView()
      }
    }
  }
}

extension MailProvider {
  var symbol: String {
    switch self {
    case .gmail: "envelope.fill"
    case .iCloud: "icloud.fill"
    case .fastmail: "bolt.fill"
    case .custom: "server.rack"
    }
  }

  var colors: [Color] {
    switch self {
    case .gmail: [Color(hex: 0xea4335), Color(hex: 0xc5221f)]
    case .iCloud: [Color(hex: 0x5ac8fa), Color(hex: 0x007aff)]
    case .fastmail: [Color(hex: 0x3b82f6), Color(hex: 0x1d4ed8)]
    case .custom: [Color(hex: 0x6b7280), Color(hex: 0x374151)]
    }
  }

  var pickerName: String {
    switch self {
    case .gmail: "Gmail"
    case .iCloud: "iCloud"
    case .fastmail: "Fastmail"
    case .custom: "Other"
    }
  }
}

extension SMTPServer {
  var summary: String {
    "\(host) · port \(port) · \(security == .implicitTLS ? "TLS" : "STARTTLS")"
  }
}
