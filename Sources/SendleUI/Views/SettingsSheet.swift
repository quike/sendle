import SendleDomain
import SwiftUI

/// Settings slide up over the card: a front page of sections with a search, then a page per
/// section. Each page is its own view, so a future window can show them beside a sidebar.
struct SettingsSheet: View {
  let panel: PanelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let settings = panel.settings
    VStack(alignment: .leading, spacing: 0) {
      SettingsHeader(panel: panel)
      ZStack(alignment: .top) {
        if let section = settings.section {
          VStack(alignment: .leading, spacing: 0) {
            ScrollView {
              page(section).padding(.top, 14).padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            if section == .sender, settings.hasEmailSetup {
              SaveRow(panel: panel)
            }
          }
          .transition(motion(section))
        } else {
          SettingsFrontPage(panel: panel).transition(motion(nil))
        }
      }
    }
    .animation(ScreenMotion.animation(reduceMotion: reduceMotion), value: settings.section == nil)
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CardBackground())
  }

  private func motion(_ section: SettingsSection?) -> AnyTransition {
    ScreenMotion.settingsPage(section, reduceMotion: reduceMotion).transition
  }

  @ViewBuilder
  private func page(_ section: SettingsSection) -> some View {
    switch section {
    case .general: GeneralPage(panel: panel)
    case .kindle: KindlePage(panel: panel)
    case .sender: SenderPage(panel: panel)
    case .usb: USBPage(panel: panel)
    case .lookup: LookupPage(panel: panel)
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
          .lineLimit(2)
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
    case .lookup: "globe"
    }
  }

  private var colors: [Color] {
    switch section {
    case .general: [Color(hex: 0x6b7280), Color(hex: 0x374151)]
    case .kindle: [Theme.brandStart, Theme.accent]
    case .sender: [Color(hex: 0xa855f7), Theme.brandStart]
    case .usb: [Color(hex: 0x22c55e), Color(hex: 0x15803d)]
    case .lookup: [Color(hex: 0x38bdf8), Color(hex: 0x0369a1)]
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
  func settingsHighlight(_ isMarked: Bool) -> some View {
    background(
      isMarked ? Theme.accent.opacity(0.18) : .clear,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .animation(.easeOut(duration: 0.6), value: isMarked)
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
      LaunchAtLoginRow(settings: settings).settingsHighlight(settings.highlighted == .launchAtLogin)
      SectionLabel("Library")
      SettingsGroup {
        HStack(spacing: 10) {
          RowText(
            title: "Controls",
            detail: "The send and A–Z bars, in the panel or on cards beside it.")
          Spacer(minLength: 8)
          SegmentedSwitch(
            label: "Controls", options: [ControlsStyle.attached, .floating],
            selection: settings.controls, title: { $0 == .attached ? "Attached" : "Floating" }
          ) { style in Task { await settings.setControls(style) } }
        }
        .padding(12)
        .settingsHighlight(settings.highlighted == .controls)
        RowDivider()
        HStack(spacing: 10) {
          RowText(title: "A–Z bar", detail: "Shown while the library is sorted by title or author.")
          Spacer(minLength: 8)
          SegmentedSwitch(
            label: "A–Z bar", options: [JumpBarStyle.full, .compact],
            selection: settings.jumpBar, title: { $0 == .full ? "Full" : "Compact" }
          ) { style in Task { await settings.setJumpBar(style) } }
        }
        .padding(12)
        .settingsHighlight(settings.highlighted == .jumpBar)
        RowDivider()
        HStack(spacing: 10) {
          RowText(
            title: "Sort authors by",
            detail:
              "Also how Sendle writes authors into the books it sends, so your Kindle files them the same way."
          )
          Spacer(minLength: 8)
          SegmentedSwitch(
            label: "Sort authors by", options: [AuthorSort.surname, .firstName],
            selection: settings.authorSort, title: { $0 == .surname ? "Surname" : "First name" }
          ) { sort in Task { await settings.setAuthorSort(sort) } }
        }
        .padding(12)
        .settingsHighlight(settings.highlighted == .authorSort)
        RowDivider()
        HStack(spacing: 10) {
          RowText(
            title: "Show book format",
            detail:
              "A small format label, like EPUB or PDF, on covers in the library and on the Kindle.")
          Spacer(minLength: 8)
          Toggle(
            "Show book format",
            isOn: Binding(
              get: { settings.showsFormat },
              set: { shows in Task { await settings.setShowsFormat(shows) } })
          )
          .toggleStyle(.switch)
          .labelsHidden()
        }
        .padding(12)
        .settingsHighlight(settings.highlighted == .showFormat)
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
        .settingsHighlight(settings.highlighted == .showLogs)
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
        .settingsHighlight(settings.highlighted == .kindleAddresses)
        if let error = settings.kindleAddressError {
          FieldNote(text: error, color: Theme.danger)
        } else if let warning = settings.kindleAddressWarning {
          FieldNote(text: warning, color: Theme.warm)
        }
        FieldNote(text: "Books sent by email go to the active address.", color: Theme.faint)
        ApprovedSendersNote { url in Task { await panel.perform(.openURL(url)) } }
          .settingsHighlight(settings.highlighted == .approvedSenders)
      } else {
        SetupFirstNote(panel: panel)
      }
    }
  }
}

private struct KindleAddressRow: View {
  let settings: SettingsViewModel
  let address: KindleEmail
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .animation(reduceMotion ? nil : Theme.press, value: isActive)
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
          .foregroundStyle(Theme.link)
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
        .foregroundStyle(Theme.link)
        .accessibilityHidden(true)
      TextField(
        "Add address", text: $settings.newKindleAddress,
        prompt: Text("Add address, like name@kindle.com").foregroundStyle(Theme.faint)
      )
      .textFieldStyle(.plain)
      .font(.system(size: 12))
      if !settings.newKindleAddress.isEmpty {
        Button("Add") { Task { await settings.addKindleAddress() } }
          .buttonStyle(SecondaryButtonStyle())
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .settingsHighlight(settings.highlighted == .addAddress)
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
        SendTestRow(
          form: settings.form,
          showLogs: panel.showsLogs ? { panel.openLogs(revealing: .sendTest) } : nil
        ) {
          Task { await panel.sendTest(from: settings.form) }
        }
        .settingsHighlight(settings.highlighted == .sendTest)
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
      VStack(alignment: .leading, spacing: 10) {
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
              .foregroundStyle(Theme.link)
          }
        }
      }
      .settingsHighlight(settings.highlighted == .bokoLocation)
      if let error = settings.bokoError {
        FieldNote(text: error, color: Theme.danger)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glass(cornerRadius: 14)
    .settingsHighlight(settings.highlighted == .boko)
  }
}

/// Which catalogues a book's details can be looked up in, and the key Google Books needs.
private struct LookupPage: View {
  let panel: PanelModel

  var body: some View {
    let settings = panel.settings
    VStack(alignment: .leading, spacing: 12) {
      SettingsGroup {
        ForEach(LookupSource.allCases, id: \.self) { source in
          if source != LookupSource.allCases.first { RowDivider() }
          LookupSourceRow(settings: settings, source: source)
          if source == .googleBooks {
            GoogleKeyField(settings: settings) { url in
              Task { await panel.perform(.openURL(url)) }
            }
          }
        }
      }
      .settingsHighlight(settings.highlighted == .lookupSources)
      FieldNote(
        text:
          "Sendle only goes online when you press 🌐 in a book's details, and sends the book's "
          + "ISBN, or its title and author, to the sources that are on.",
        color: Theme.faint
      )
      .padding(.horizontal, 4)
    }
  }
}

private struct LookupSourceRow: View {
  let settings: SettingsViewModel
  let source: LookupSource

  var body: some View {
    let isOn = settings.lookupSources.contains(source)
    HStack(spacing: 10) {
      RowText(title: source.name, detail: detail)
      Spacer(minLength: 8)
      Toggle(
        source.name,
        isOn: Binding(
          get: { isOn },
          set: { on in Task { await settings.setLookupSource(source, isOn: on) } })
      )
      .toggleStyle(.switch)
      .labelsHidden()
      .disabled(source == .googleBooks && !settings.hasGoogleKey && !isOn)
    }
    .padding(12)
  }

  private var detail: String {
    switch source {
    case .openLibrary: "Free and open. Finds most printed editions."
    case .googleBooks: "Needs your own free API key."
    case .appleBooks: "Title, author and a large cover. It has no dates or ISBNs for your edition."
    }
  }
}

/// Under Google Books: a field for the key until one is saved, then a note that it is.
private struct GoogleKeyField: View {
  static let help = URL(string: "https://developers.google.com/books/docs/v1/using#APIKey")

  @Bindable var settings: SettingsViewModel
  let open: (URL) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if settings.hasGoogleKey {
        HStack(spacing: 8) {
          Text("Key saved in your Keychain")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.muted)
          Spacer(minLength: 6)
          Button("Remove") { Task { await settings.removeGoogleKey() } }
            .buttonStyle(SecondaryButtonStyle())
        }
      } else {
        HStack(spacing: 8) {
          GlassTextField(
            label: "API key", prompt: "API key", text: $settings.googleKey, isSecure: true)
          Button("Save") { Task { await settings.saveGoogleKey() } }
            .buttonStyle(SecondaryButtonStyle())
        }
        if let help = Self.help {
          Button("Get a key ↗") { open(help) }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Theme.link)
        }
      }
      if let error = settings.googleKeyError {
        FieldNote(text: error, color: Theme.danger)
      }
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 12)
    .settingsHighlight(settings.highlighted == .googleBooksKey)
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
