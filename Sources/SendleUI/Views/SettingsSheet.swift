import SendleDomain
import SwiftUI

/// Settings slide up over the card: a front page of sections with a search, then a page per
/// section. Each page is its own view, so a future window can show them beside a sidebar.
struct SettingsSheet: View {
  let panel: PanelModel

  var body: some View {
    let settings = panel.settings
    VStack(alignment: .leading, spacing: 0) {
      SettingsHeader(panel: panel)
      if let section = settings.section {
        ScrollView {
          page(section).padding(.top, 14).padding(.bottom, 8)
        }
        .scrollIndicators(.never)
        if section == .sender, settings.hasEmailSetup {
          SaveRow(panel: panel)
        }
      } else {
        SettingsFrontPage(panel: panel)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CardBackground())
  }

  @ViewBuilder
  private func page(_ section: SettingsSection) -> some View {
    switch section {
    case .general: GeneralPage(panel: panel)
    case .kindle: KindlePage(panel: panel)
    case .sender: SenderPage(panel: panel)
    case .usb: USBPage(panel: panel)
    }
  }
}

private struct SettingsHeader: View {
  let panel: PanelModel

  var body: some View {
    let settings = panel.settings
    HStack(spacing: 10) {
      if settings.section != nil {
        Button {
          settings.show(nil)
        } label: {
          Image(systemName: "chevron.left")
        }
        .buttonStyle(CircleButtonStyle())
        .help("All settings")
        .accessibilityLabel("All settings")
      }
      Text(settings.section?.title ?? "Settings").font(.system(size: 15, weight: .semibold))
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
  }
}

/// The search and one row per section, or the settings the search found.
private struct SettingsFrontPage: View {
  let panel: PanelModel

  var body: some View {
    let settings = panel.settings
    VStack(alignment: .leading, spacing: 12) {
      SettingsSearchField(settings: settings)
      if settings.query.trimmingCharacters(in: .whitespaces).isEmpty {
        SettingsGroup {
          ForEach(SettingsSection.allCases, id: \.self) { section in
            if section != SettingsSection.allCases.first { RowDivider() }
            Button {
              settings.show(section)
            } label: {
              SettingsLinkRow(
                section: section, title: section.title, detail: settings.summary(of: section))
            }
            .buttonStyle(.plain)
          }
        }
      } else if settings.results.isEmpty {
        FieldNote(text: "No settings match.", color: Theme.faint).padding(.horizontal, 4)
      } else {
        SettingsGroup {
          ForEach(settings.results, id: \.self) { item in
            if item != settings.results.first { RowDivider() }
            Button {
              settings.choose(item)
            } label: {
              SettingsLinkRow(section: item.section, title: item.title, detail: item.section.title)
            }
            .buttonStyle(.plain)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.top, 12)
  }
}

private struct SettingsSearchField: View {
  @Bindable var settings: SettingsViewModel

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.faint)
        .accessibilityHidden(true)
      TextField(
        "Search settings", text: $settings.query,
        prompt: Text("Search settings").foregroundStyle(Theme.faint)
      )
      .textFieldStyle(.plain)
      .font(.system(size: 12))
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 8)
    .glass(cornerRadius: 12)
  }
}

/// A row that opens a section: its icon, name, a line about it and a chevron.
private struct SettingsLinkRow: View {
  let section: SettingsSection
  let title: String
  let detail: String

  var body: some View {
    HStack(spacing: 10) {
      SectionTile(section: section)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 12.5, weight: .semibold))
        Text(detail)
          .font(.system(size: 10.5))
          .foregroundStyle(detail == "boko found" ? Theme.live : Theme.muted)
          .lineLimit(1)
      }
      Spacer(minLength: 6)
      Image(systemName: "chevron.right")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Theme.faint)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }
}

/// Each section's SF Symbol on its own gradient.
struct SectionTile: View {
  let section: SettingsSection

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 26, height: 26)
      .background(
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .accessibilityHidden(true)
  }

  private var symbol: String {
    switch section {
    case .general: "gearshape.fill"
    case .kindle: "book.closed.fill"
    case .sender: "paperplane.fill"
    case .usb: "cable.connector"
    }
  }

  private var colors: [Color] {
    switch section {
    case .general: [Color(hex: 0x6b7280), Color(hex: 0x374151)]
    case .kindle: [Theme.brandStart, Theme.accent]
    case .sender: [Color(hex: 0xa855f7), Theme.brandStart]
    case .usb: [Color(hex: 0x22c55e), Color(hex: 0x15803d)]
    }
  }
}

/// Rows on one glass surface; `RowDivider` goes between them.
struct SettingsGroup<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .glass(cornerRadius: 14)
  }
}

struct RowDivider: View {
  var body: some View {
    Rectangle().fill(Theme.line).frame(height: 1)
  }
}

extension View {
  /// Marks the setting a search result led to, for a moment.
  func settingsHighlight(_ item: SettingsItem, in settings: SettingsViewModel) -> some View {
    background(
      settings.highlighted == item ? Theme.accent.opacity(0.18) : .clear,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .animation(.easeOut(duration: 0.6), value: settings.highlighted)
  }
}

private struct SaveRow: View {
  let panel: PanelModel

  var body: some View {
    let form = panel.settings.form
    HStack(spacing: 8) {
      if let error = form.saveError {
        FieldNote(text: error, color: Theme.danger)
      }
      Spacer(minLength: 0)
      Button("Save") { Task { await panel.saveSettings() } }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(form.isSaving)
    }
    .padding(.top, 8)
  }
}

// MARK: Pages

private struct GeneralPage: View {
  let panel: PanelModel

  var body: some View {
    let settings = panel.settings
    VStack(alignment: .leading, spacing: 12) {
      LaunchAtLoginRow(settings: settings).settingsHighlight(.launchAtLogin, in: settings)
      SectionLabel("Library")
      SettingsGroup {
        HStack(spacing: 10) {
          RowText(title: "A–Z bar", detail: "Shown while the library is sorted by title or author.")
          Spacer(minLength: 8)
          Picker(
            "A–Z bar",
            selection: Binding(
              get: { settings.jumpBar }, set: { style in Task { await settings.setJumpBar(style) } }
            )
          ) {
            Text("Full").tag(JumpBarStyle.full)
            Text("Compact").tag(JumpBarStyle.compact)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
        }
        .padding(12)
        .settingsHighlight(.jumpBar, in: settings)
      }
      SectionLabel("Troubleshooting")
      SettingsGroup {
        HStack(spacing: 10) {
          RowText(
            title: "Show logs",
            detail: "Adds a logs button to the panel. Passwords are never shown.")
          Spacer(minLength: 8)
          Toggle(
            "Show logs",
            isOn: Binding(
              get: { settings.showsLogs },
              set: { shows in Task { await settings.setShowsLogs(shows) } })
          )
          .toggleStyle(.switch)
          .labelsHidden()
        }
        .padding(12)
        .settingsHighlight(.showLogs, in: settings)
      }
    }
  }
}

private struct RowText: View {
  let title: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title).font(.system(size: 12.5, weight: .semibold))
      Text(detail)
        .font(.system(size: 10.5))
        .foregroundStyle(Theme.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// What the Kindle and Sender pages show before there is any email setup.
private struct SetupFirstNote: View {
  let panel: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Sendle needs your Kindle's email address and an account to send from.")
        .font(.system(size: 12))
        .foregroundStyle(Color.white.opacity(0.75))
        .fixedSize(horizontal: false, vertical: true)
      Button("Set up Kindle email") {
        panel.closeSettings()
        panel.showSetup(at: .kindleEmail)
      }
      .buttonStyle(PrimaryButtonStyle())
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(cornerRadius: 14)
  }
}

private struct KindlePage: View {
  let panel: PanelModel

  var body: some View {
    let settings = panel.settings
    VStack(alignment: .leading, spacing: 12) {
      if settings.hasEmailSetup {
        SectionLabel("Kindle addresses")
        SettingsGroup {
          ForEach(settings.kindleAddresses, id: \.self) { address in
            KindleAddressRow(settings: settings, address: address)
            RowDivider()
          }
          AddKindleAddressRow(settings: settings)
        }
        .settingsHighlight(.kindleAddresses, in: settings)
        if let error = settings.kindleAddressError {
          FieldNote(text: error, color: Theme.danger)
        } else if let warning = settings.kindleAddressWarning {
          FieldNote(text: warning, color: Theme.warm)
        }
        FieldNote(text: "Books sent by email go to the active address.", color: Theme.faint)
        ApprovedSendersNote { url in Task { await panel.perform(.openURL(url)) } }
          .settingsHighlight(.approvedSenders, in: settings)
      } else {
        SetupFirstNote(panel: panel)
      }
    }
  }
}

private struct KindleAddressRow: View {
  let settings: SettingsViewModel
  let address: KindleEmail

  var body: some View {
    let isActive = settings.activeKindleAddress == address
    HStack(spacing: 10) {
      Button {
        Task { await settings.activate(address) }
      } label: {
        HStack(spacing: 10) {
          Circle()
            .strokeBorder(isActive ? Theme.accent : Theme.faint, lineWidth: isActive ? 4 : 1.5)
            .frame(width: 14, height: 14)
          Text(address.rawValue).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
          Spacer(minLength: 6)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(address.rawValue)
      .accessibilityAddTraits(isActive ? .isSelected : [])
      .help(isActive ? "Books go here" : "Send books here")
      if isActive {
        Text("Active")
          .font(.system(size: 9.5, weight: .bold))
          .foregroundStyle(Color(hex: 0x9cc2ff))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
      }
      Menu {
        Button("Remove") { Task { await settings.remove(address) } }
          .disabled(isActive)
      } label: {
        Image(systemName: "ellipsis").frame(width: 20, height: 20).contentShape(Rectangle())
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      .foregroundStyle(Theme.faint)
      .help(isActive ? "Make another address active before removing this one" : "More")
      .accessibilityLabel("More for \(address.rawValue)")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
  }
}

private struct AddKindleAddressRow: View {
  @Bindable var settings: SettingsViewModel

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "plus")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color(hex: 0x9cc2ff))
        .accessibilityHidden(true)
      TextField(
        "Add address", text: $settings.newKindleAddress,
        prompt: Text("Add address, like name@kindle.com").foregroundStyle(Theme.faint)
      )
      .textFieldStyle(.plain)
      .font(.system(size: 12))
      .onSubmit { Task { await settings.addKindleAddress() } }
      if !settings.newKindleAddress.isEmpty {
        Button("Add") { Task { await settings.addKindleAddress() } }
          .buttonStyle(SecondaryButtonStyle())
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .settingsHighlight(.addAddress, in: settings)
  }
}

private struct SenderPage: View {
  let panel: PanelModel

  var body: some View {
    let settings = panel.settings
    VStack(alignment: .leading, spacing: 12) {
      if settings.hasEmailSetup {
        SenderFields(form: settings.form, highlighted: settings.highlighted) { url in
          Task { await panel.perform(.openURL(url)) }
        }
        SendTestRow(form: settings.form) {
          Task { await panel.sendTest(from: settings.form) }
        }
        .settingsHighlight(.sendTest, in: settings)
      } else {
        SetupFirstNote(panel: panel)
      }
    }
  }
}

/// Whether boko is there to turn EPUBs into AZW3, and where (spec §3.5).
private struct USBPage: View {
  static let download = URL(string: "https://github.com/zacharydenton/boko#install")

  let panel: PanelModel

  var body: some View {
    let settings = panel.settings
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: settings.boko == nil ? "questionmark.circle" : "checkmark.circle.fill")
          .font(.system(size: 18))
          .foregroundStyle(settings.boko == nil ? Theme.warm : Theme.live)
          .accessibilityHidden(true)
        RowText(title: settings.bokoTitle, detail: settings.bokoNote)
      }
      if let path = (settings.boko ?? settings.chosenBoko)?.path {
        Text(path)
          .font(.system(size: 10.5, design: .monospaced))
          .foregroundStyle(Theme.muted)
          .lineLimit(2)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }
      HStack(spacing: 8) {
        Button("Choose…") { Task { await panel.chooseBoko() } }
          .buttonStyle(SecondaryButtonStyle())
          .help("Point Sendle at a boko somewhere else")
        if settings.chosenBoko != nil {
          Button("Reset") { Task { await settings.resetBoko() } }
            .buttonStyle(SecondaryButtonStyle())
            .help("Look for boko in the usual folders again")
        }
        Spacer(minLength: 0)
        if settings.boko == nil, settings.chosenBoko == nil, let download = Self.download {
          Button("Get boko ↗") { Task { await panel.perform(.openURL(download)) } }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color(hex: 0x9cc2ff))
        }
      }
      if let error = settings.bokoError {
        FieldNote(text: error, color: Theme.danger)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(cornerRadius: 14)
    .settingsHighlight(.boko, in: settings)
  }
}

private struct LaunchAtLoginRow: View {
  let settings: SettingsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        RowText(title: "Launch at login", detail: "Sendle starts quietly in the menu bar.")
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
