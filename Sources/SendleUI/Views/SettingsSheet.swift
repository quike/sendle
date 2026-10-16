import SwiftUI

/// Settings slide up over the card instead of opening a window.
struct SettingsSheet: View {
  let panel: PanelModel

  var body: some View {
    let settings = panel.settings
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Settings").font(.system(size: 15, weight: .semibold))
        Spacer()
        Button {
          panel.closeSettings()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(CircleButtonStyle())
        .help("Close (Esc)")
        .accessibilityLabel("Close settings")
      }
      Picker("Section", selection: Bindable(settings).section) {
        Text("Kindle").tag(SettingsSection.kindle)
        Text("Sender").tag(SettingsSection.sender)
        Text("General").tag(SettingsSection.general)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.top, 12)
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          switch settings.section {
          case .kindle:
            KindleAddressField(form: settings.form)
            ApprovedSendersNote { url in Task { await panel.perform(.openURL(url)) } }
          case .sender:
            SenderFields(form: settings.form) { url in
              Task { await panel.perform(.openURL(url)) }
            }
            SendTestRow(form: settings.form) {
              Task { await panel.sendTest(from: settings.form) }
            }
          case .general:
            LaunchAtLoginRow(settings: settings)
          }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
      }
      .scrollIndicators(.never)
      if settings.section != .general {
        HStack(spacing: 8) {
          if let error = settings.form.saveError {
            FieldNote(text: error, color: Theme.danger)
          }
          Spacer(minLength: 0)
          Button("Save") { Task { await panel.saveSettings() } }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(settings.form.isSaving)
        }
        .padding(.top, 8)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CardBackground())
  }
}

private struct LaunchAtLoginRow: View {
  let settings: SettingsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 1) {
          Text("Launch at login").font(.system(size: 12.5, weight: .semibold))
          Text("Sendle starts quietly in the menu bar.")
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.muted)
        }
        Spacer(minLength: 8)
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: {
              settings.launchAtLogin == .enabled || settings.launchAtLogin == .requiresApproval
            },
            set: { settings.setLaunchAtLogin($0) })
        )
        .toggleStyle(.switch)
        .labelsHidden()
        .disabled(settings.launchAtLogin == .unavailable)
      }
      if let note = settings.launchAtLoginNote {
        FieldNote(text: note, color: Theme.warm)
      }
      if let error = settings.launchAtLoginError {
        FieldNote(text: error, color: Theme.danger)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(cornerRadius: 14)
  }
}
