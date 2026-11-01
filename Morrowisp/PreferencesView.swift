// File: PreferencesView.swift
// Description: 타이머, 알림, Obsidian 연동, 일반 설정을 모아 둔 설정 창입니다.

import SwiftUI
import AppKit
import UserNotifications

/// 설정 창 왼쪽 목록의 칸. 마지막에 연 칸을 기억합니다 (rawValue 로 저장).
enum SettingsSection: String, CaseIterable, Identifiable {
    case timer, notifications, notes, shortcuts, muninn, general
    var id: String { rawValue }

    /// 저장해 둔 값을 읽습니다. 모르는 값(옛 버전·지워진 칸)이면 타이머로.
    init(stored: String) { self = SettingsSection(rawValue: stored) ?? .timer }

    var title: LocalizedStringKey {
        switch self {
        case .timer: "Timer"
        case .notifications: "Notifications"
        case .notes: "Obsidian notes"
        case .shortcuts: "Shortcuts"
        case .muninn: "Muninn"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .timer: "timer"
        case .notifications: "bell"
        case .notes: "doc.text"
        case .shortcuts: "square.2.layers.3d"
        case .muninn: "checklist"
        case .general: "gearshape"
        }
    }
}

/// macOS 시스템 설정처럼 왼쪽 목록에서 칸을 고릅니다.
struct PreferencesView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var obsidian = ObsidianExporter.shared
    @ObservedObject var updates = UpdateController.shared
    @ObservedObject var muninn = MuninnService.shared
    @AppStorage("settingsSection") private var storedSection = SettingsSection.timer.rawValue

    private var selection: Binding<SettingsSection?> {
        Binding(get: { SettingsSection(stored: storedSection) },
                set: { if let section = $0 { storedSection = section.rawValue } })
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: selection) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            detail(for: SettingsSection(stored: storedSection))
                .navigationTitle(SettingsSection(stored: storedSection).title)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(width: 720, height: 500)
    }

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        switch section {
        case .timer: TimerSettingsTab(settings: settings)
        case .notifications: NotificationSettingsTab(settings: settings)
        case .notes: ObsidianSettingsTab(obsidian: obsidian)
        case .shortcuts: ShortcutSettingsTab(settings: settings)
        case .muninn: MuninnSettingsTab(service: muninn)
        case .general: GeneralSettingsTab(settings: settings, updates: updates)
        }
    }
}

// MARK: - 타이머

struct TimerSettingsTab: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Session lengths") {
                Stepper("Focus: \(settings.focusDurationInMinutes.formatted()) min",
                        value: $settings.focusDurationInMinutes, in: 1...120)
                Stepper("Short break: \(settings.shortBreakDurationInMinutes.formatted()) min",
                        value: $settings.shortBreakDurationInMinutes, in: 1...60)
                Stepper("Long break: \(settings.longBreakDurationInMinutes.formatted()) min",
                        value: $settings.longBreakDurationInMinutes, in: 1...60)
                Stepper("Long break every \(settings.longBreakInterval.formatted()) focus sessions",
                        value: $settings.longBreakInterval, in: 2...10)
            }
            Section("Session transitions") {
                Toggle("Transition support", isOn: $settings.transitionManagementEnabled)
                Toggle("Start breaks automatically after focus", isOn: $settings.autoStartBreaks)
                Toggle("Start focus automatically after breaks", isOn: $settings.autoStartFocus)
                Text("When on, choose a break or 10 more minutes after focus ends. Task and reward fields, missions, and summaries are also shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if settings.transitionManagementEnabled {
                RewardListSettings(store: settings.rewardList)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 알림

struct NotificationSettingsTab: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.openURL) private var openURL
    @State private var hasNotificationPermission = true

    var body: some View {
        Form {
            Section("Notification sound") {
                Picker("Session end sound", selection: $settings.notificationSoundName) {
                    Text("None").tag(AppSettings.soundOff)
                    Divider()
                    ForEach(AppSettings.availableSounds, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .onChange(of: settings.notificationSoundName) { _, newValue in
                    guard newValue != AppSettings.soundOff else { return }
                    NSSound(named: newValue)?.play()
                }
                Button("Preview sound") {
                    guard settings.notificationSoundName != AppSettings.soundOff else { return }
                    NSSound(named: settings.notificationSoundName)?.play()
                }
                .disabled(settings.notificationSoundName == AppSettings.soundOff)
            }
            if !hasNotificationPermission {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Allow notifications in System Settings to receive banners.", systemImage: "bell.badge.fill")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open notification settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                openURL(url)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
            hasNotificationPermission = (notificationSettings.authorizationStatus == .authorized)
        }
    }
}

// MARK: - Obsidian

struct ObsidianSettingsTab: View {
    @Environment(\.locale) private var locale
    @ObservedObject var obsidian = ObsidianExporter.shared

    var body: some View {
        Form {
            Section("Daily notes") {
                Toggle("Write to daily notes when sessions end", isOn: $obsidian.isEnabled)
                if obsidian.isEnabled {
                    HStack {
                        Image(systemName: obsidian.isFolderSelected ? "folder.fill" : "folder.badge.questionmark")
                            .foregroundStyle(obsidian.isFolderSelected ? Color.accentColor : .orange)
                        Text(obsidian.folderName ?? String(localized: "No folder selected", bundle: AppLocalization.bundle(for: locale), locale: locale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Choose folder") { obsidian.chooseFolder() }
                    }
                }
            }
            Section {
                Text("Session records and daily totals are added to the \"\(ObsidianExporter.sectionHeading)\" section of daily notes (yyyy-MM-dd.md). The rest of each note stays as it is.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 단축어

struct ShortcutSettingsTab: View {
    @Environment(\.locale) private var locale
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Shortcuts for focus") {
                shortcutRow(String(localized: "When focus starts", bundle: AppLocalization.bundle(for: locale), locale: locale), name: $settings.focusStartShortcut)
                shortcutRow(String(localized: "When focus ends", bundle: AppLocalization.bundle(for: locale), locale: locale), name: $settings.focusEndShortcut)
            }
            Section {
                Text("Enter the exact names from the Shortcuts app, such as shortcuts that turn Do Not Disturb on and off. Leave a field empty to skip it. Extending focus runs the start shortcut again. Skipping, resetting, or quitting focus also runs the end shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, name: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            HStack {
                TextField(title, text: name, prompt: Text("Shortcut name"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity)
                Button("Try running") { URLShortcutRunner().run(named: name.wrappedValue) }
                    .fixedSize()
                    .disabled(name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

// MARK: - 일반

struct GeneralSettingsTab: View {
    @Environment(\.locale) private var locale
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var updates = UpdateController.shared

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var lastCheckText: String {
        updates.lastCheckDate?.formatted(.dateTime.locale(locale).year().month().day().hour().minute()) ?? String(localized: "Not yet", bundle: AppLocalization.bundle(for: locale), locale: locale)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Show remaining time in the menu bar", isOn: $settings.showTimeInMenuBar)
            }
            UpdateSettingsSection(
                disabledReason: updates.localizedStatusText(locale: locale),
                automaticallyChecks: $updates.automaticallyChecks,
                lastCheckText: lastCheckText,
                availableVersion: updates.availableVersion,
                pendingVersion: updates.pendingVersion,
                canInstallNow: updates.canInstallPendingUpdate,
                installing: updates.installInProgress,
                canCheckNow: updates.canCheckForUpdates,
                checkNow: { updates.checkForUpdates() },
                installNow: { updates.installPendingUpdateNow() }
            )
            Section("About") {
                LabeledContent("Version", value: versionString)
                Text("© 2026 SW Square")
                    .foregroundStyle(.secondary)
                Link("View on GitHub", destination: URL(string: "https://github.com/JeongSeongWon1116/Morrowisp")!)
            }
        }
        .formStyle(.grouped)
    }
}

/// 설정 > 일반의 "업데이트" 묶음. 상태를 값으로 받아, 업데이터 없이도 그려 볼 수 있습니다.
struct UpdateSettingsSection: View {
    @Environment(\.locale) private var locale
    /// 업데이트를 쓰지 않는 빌드이면 그 이유, 쓰고 있으면 nil
    let disabledReason: String?
    @Binding var automaticallyChecks: Bool
    let lastCheckText: String
    /// 찾았지만 곧바로 설치할 수 없는 새 버전 (Sparkle 의 안내 창에서 이어 가는 업데이트)
    let availableVersion: String?
    /// 받아 두고 설치를 기다리는 버전
    let pendingVersion: String?
    let canInstallNow: Bool
    /// 받아 둔 업데이트의 설치를 시작해 앱이 꺼지기를 기다리는 중인지
    let installing: Bool
    let canCheckNow: Bool
    let checkNow: () -> Void
    let installNow: () -> Void

    var body: some View {
        Section("Updates") {
            if let disabledReason {
                Text("Automatic updates are unavailable — \(disabledReason).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Check for updates automatically", isOn: $automaticallyChecks)
                LabeledContent("Last checked", value: lastCheckText)
                if let pendingVersion {
                    LabeledContent("Downloaded version \(pendingVersion)") {
                        Button(installing ? String(localized: "Installing…", bundle: AppLocalization.bundle(for: locale), locale: locale) : String(localized: "Install and reopen now", bundle: AppLocalization.bundle(for: locale), locale: locale), action: installNow)
                            .disabled(!canInstallNow)
                    }
                } else {
                    if let availableVersion {
                        Text("Version \(availableVersion) is available.")
                    }
                    Button("Check now", action: checkNow)
                        .disabled(!canCheckNow)
                }
                Text(Self.caption(hasPending: pendingVersion != nil, automaticallyChecks: automaticallyChecks, installing: installing, locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 아래 설명 한 줄. 지금 설정에서 실제로 일어나는 일만 적습니다.
    nonisolated static func caption(hasPending: Bool, automaticallyChecks: Bool, installing: Bool = false, locale: Locale = .current) -> String {
        if hasPending {
            if installing { return String(localized: "Installation has started. The app will close and reopen shortly.", bundle: AppLocalization.bundle(for: locale), locale: locale) }
            return String(localized: "A new version is downloaded. Use the button above or Update in the menu bar popover to install and reopen. It also installs when you quit. Further checks wait until installation.", bundle: AppLocalization.bundle(for: locale), locale: locale)
        }
        if !automaticallyChecks {
            return String(localized: "Automatic checks are off. Updates are checked only when you choose Check now.", bundle: AppLocalization.bundle(for: locale), locale: locale)
        }
        return String(localized: "New versions are downloaded and shown as a dot on the menu bar icon. Choose Update to install and reopen. A downloaded update also installs when you quit.", bundle: AppLocalization.bundle(for: locale), locale: locale)
    }
}
