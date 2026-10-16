import SwiftUI

struct SetupScreen: View {
  let panel: PanelModel

  var body: some View {
    let setup = panel.setup
    VStack(alignment: .leading, spacing: 0) {
      PanelHeader(title: "Welcome to Sendle", subtitle: setup.stepLabel) { EmptyView() }
      HStack(spacing: 6) {
        ForEach(SetupStep.allCases, id: \.self) { step in
          Capsule()
            .fill(step.rawValue <= setup.step.rawValue ? Theme.accent : Color.white.opacity(0.1))
            .frame(height: 4)
        }
      }
      .padding(.top, 14)
      ScrollView {
        Group {
          switch setup.step {
          case .libraryAccess: LibraryAccessStep(panel: panel)
          case .kindleEmail: KindleEmailStep(panel: panel)
          case .sender: SenderStep(panel: panel)
          }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
      }
      .scrollIndicators(.never)
    }
    .padding(14)
  }
}

struct SetupHero: View {
  let symbol: String
  let title: String
  let text: String

  var body: some View {
    VStack(spacing: 0) {
      Image(systemName: symbol)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(Color(hex: 0xb9c8ff))
        .frame(width: 56, height: 56)
        .background(
          LinearGradient(
            colors: [Theme.accent.opacity(0.25), Theme.brandStart.opacity(0.25)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
          in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Theme.brandStart.opacity(0.4))
        )
        .padding(.bottom, 12)
      Text(title).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.center)
      Text(text)
        .font(.system(size: 11.5))
        .foregroundStyle(Color.white.opacity(0.62))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 6)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 8)
    .padding(.top, 14)
    .padding(.bottom, 14)
  }
}

private struct LibraryAccessStep: View {
  let panel: PanelModel

  /// Markdown, so the button and app names stand out.
  private let steps = [
    "1. Click **Open Privacy Settings**.",
    "2. Turn on **Sendle** under Full Disk Access. If it isn't listed, click **+** and choose "
      + "Sendle, or drag it in from Finder.",
    "3. Come back. Sendle notices by itself.",
  ]

  var body: some View {
    VStack(spacing: 0) {
      SetupHero(
        symbol: "lock.shield", title: "Let Sendle see your Books library",
        text: "macOS keeps the Books library private. Sendle only reads it, never changes it, and "
          + "nothing leaves your Mac unless you send a book.")
      VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
          Text(LocalizedStringKey(step)).fixedSize(horizontal: false, vertical: true)
        }
      }
      .font(.system(size: 11))
      .foregroundStyle(Color.white.opacity(0.7))
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
      Button("Open Privacy Settings") { Task { await panel.perform(.openPrivacySettings) } }
        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
        .padding(.top, 12)
      Button("Show Sendle in Finder") { panel.revealApp() }
        .buttonStyle(QuietButtonStyle())
        .padding(.top, 10)
      HStack(spacing: 6) {
        ProgressView().controlSize(.mini)
        Text("Checking every few seconds")
      }
      .font(.system(size: 10.5))
      .foregroundStyle(Theme.faint)
      .padding(.top, 14)
      FieldNote(
        text: "Still waiting after you turned it on? Quit Sendle from its menu and open it again.",
        color: Theme.faint
      )
      .multilineTextAlignment(.center)
      .padding(.top, 6)
    }
  }
}

private struct KindleEmailStep: View {
  let panel: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SetupHero(
        symbol: "envelope", title: "Where should books go?",
        text: "Every Kindle has a Send to Kindle address. Amazon lists it under Devices, in your "
          + "Kindle's details.")
      KindleAddressField(form: panel.setup.form)
      ApprovedSendersNote { url in Task { await panel.perform(.openURL(url)) } }
      Button("Continue") { panel.setup.continueToSender() }
        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
        .padding(.top, 2)
      Button("Set up later") { panel.skipSetup() }
        .buttonStyle(QuietButtonStyle())
        .frame(maxWidth: .infinity)
    }
  }
}

private struct SenderStep: View {
  let panel: PanelModel

  var body: some View {
    let form = panel.setup.form
    VStack(alignment: .leading, spacing: 12) {
      SetupHero(
        symbol: "paperplane", title: "Which account sends them?",
        text: "Sendle emails books from your own account with an app password, which you can "
          + "revoke at any time.")
      SenderFields(form: form) { url in Task { await panel.perform(.openURL(url)) } }
      if let error = form.saveError {
        FieldNote(text: error, color: Theme.danger)
      }
      HStack(spacing: 8) {
        Button("Back") { panel.setup.back() }
          .buttonStyle(SecondaryButtonStyle())
        Button("Save") { Task { await panel.finishSetup() } }
          .buttonStyle(PrimaryButtonStyle(fullWidth: true))
          .disabled(form.isSaving)
      }
      .padding(.top, 2)
      SendTestRow(hint: panel.settings.sendTestHint)
      Button("Set up later") { panel.skipSetup() }
        .buttonStyle(QuietButtonStyle())
        .frame(maxWidth: .infinity)
    }
  }
}
