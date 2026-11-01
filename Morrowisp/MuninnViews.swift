// File: MuninnViews.swift
// Description: Muninn 설정 칸, 팝오버의 "오늘" 묶음(할 일·다음 일정), 집중 뒤 기분 고르기.

import SwiftUI

// MARK: - 설정

struct MuninnSettingsTab: View {
    @Environment(\.locale) private var locale
    @ObservedObject var service = MuninnService.shared
    @State private var tokenDraft = ""
    @State private var tokenError = false
    @State private var testResult: Result<String, MuninnError>?
    @State private var testing = false

    private var url: URL? { MuninnClient.validatedBaseURL(service.baseURLString) }

    var body: some View {
        Form {
            Section("Muninn server") {
                TextField("Address", text: $service.baseURLString, prompt: Text(verbatim: "https://"))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                if !service.baseURLString.isEmpty && url == nil {
                    Text("Enter an address that starts with https:// or http://.")
                        .font(.caption).foregroundStyle(.orange)
                } else if url?.scheme?.lowercased() == "http" {
                    Text("Without https, the token travels unencrypted. http works only for local names and IP addresses on a trusted network.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Personal API token") {
                if service.hasToken {
                    LabeledContent("Token") {
                        HStack {
                            Text("Saved in Keychain").foregroundStyle(.secondary)
                            Button("Remove") { service.removeToken(); testResult = nil }
                        }
                    }
                }
                HStack {
                    SecureField(service.hasToken ? "New token" : "Token", text: $tokenDraft,
                                prompt: Text(service.hasToken ? "Paste a new token to replace it" : "Paste the token"))
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        do {
                            try service.saveToken(tokenDraft)
                            tokenError = false
                        } catch {
                            tokenError = true
                        }
                        tokenDraft = ""
                        testResult = nil
                    }
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if tokenError {
                    Text("Could not save the token to Keychain.").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("Test connection") {
                        testing = true
                        Task {
                            testResult = await service.testConnection()
                            testing = false
                            await service.refresh(force: true)
                        }
                    }
                    .disabled(!service.isConfigured || testing)
                    if testing { ProgressView().controlSize(.small) }
                    if let testResult { Text(Self.resultText(testResult, locale: locale)).font(.caption)
                            .foregroundStyle(Self.isSuccess(testResult) ? Color.secondary : Color.orange) }
                }
            }
            Section {
                Text("Create a token on the Muninn server (muninn token create morrowisp) and paste it here. Today's Google tasks and next event appear in the menu bar popover. Finished focus sessions, with the mood you pick, are added to the Muninn daily journal. Nothing is sent when this is empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private static func isSuccess(_ result: Result<String, MuninnError>) -> Bool {
        if case .success = result { return true }
        return false
    }

    nonisolated static func resultText(_ result: Result<String, MuninnError>, locale: Locale = .current) -> String {
        let bundle = AppLocalization.bundle(for: locale)
        switch result {
        case .success(let name):
            return name.isEmpty ? String(localized: "Connected", bundle: bundle, locale: locale)
                : String(localized: "Connected as \(name)", bundle: bundle, locale: locale)
        case .failure(.unauthorized): return String(localized: "Muninn did not accept the token", bundle: bundle, locale: locale)
        case .failure(.unreachable): return String(localized: "Could not reach Muninn", bundle: bundle, locale: locale)
        case .failure(.http(let code)): return String(localized: "Unexpected reply from Muninn (HTTP \(code))", bundle: bundle, locale: locale)
        case .failure: return String(localized: "Unexpected reply from Muninn", bundle: bundle, locale: locale)
        }
    }
}

// MARK: - 팝오버: 오늘

struct MuninnTodaySection: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject var viewModel: PomodoroViewModel
    @ObservedObject var service: MuninnService
    @ObservedObject var settings = AppSettings.shared
    @State private var completing: Set<String> = []
    private static let visibleTasks = 5

    var body: some View {
        // 분 단위 시계: "몇 분 뒤"와 짧은 집중 제안이 열린 팝오버에서도 맞게 바뀝니다.
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 5) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                if let line = quietLine {
                    Text(line).font(.caption).foregroundStyle(.secondary)
                }
                if let next = service.nextEvent {
                    Label(nextEventText(next), systemImage: "calendar")
                        .font(.caption).lineLimit(1)
                        .help(next.title)
                }
                if let offer = service.shortFocusOffer(normalMinutes: settings.focusDurationInMinutes),
                   viewModel.timerState == .idle, viewModel.currentState == .idle {
                    Button(String(localized: "Focus \(offer.focusMinutes.formatted()) min before it", bundle: AppLocalization.bundle(for: locale), locale: locale)) {
                        viewModel.startFocusSession(minutes: offer.focusMinutes)
                    }
                    .controlSize(.small)
                    .help(String(localized: "Ends 5 minutes or more before the next event", bundle: AppLocalization.bundle(for: locale), locale: locale))
                }
                let tasks = service.sortedTasks
                ForEach(tasks.prefix(Self.visibleTasks), id: \.key) { task in
                    taskRow(task)
                }
                if tasks.count > Self.visibleTasks {
                    Text("+\((tasks.count - Self.visibleTasks).formatted()) more").font(.caption2).foregroundStyle(.secondary)
                }
                if service.actionFailed {
                    Text("Could not reach Muninn. Try again later.").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .task {
            // 열려 있는 동안 60초마다. 닫으면 멈춥니다.
            while !Task.isCancelled {
                await service.refresh()
                try? await Task.sleep(for: .seconds(MuninnService.refreshInterval))
            }
        }
    }

    private var quietLine: String? {
        let bundle = AppLocalization.bundle(for: locale)
        switch service.status {
        case .unreachable: return String(localized: "Muninn is not reachable", bundle: bundle, locale: locale)
        case .unauthorized: return String(localized: "Muninn did not accept the token", bundle: bundle, locale: locale)
        case .googleDisconnected: return String(localized: "Google not connected", bundle: bundle, locale: locale)
        case .loaded where service.sortedTasks.isEmpty: return String(localized: "No tasks due today", bundle: bundle, locale: locale)
        default: return nil
        }
    }

    private func nextEventText(_ next: MuninnService.NextEvent) -> String {
        let time = next.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        let duration = Duration.seconds(max(1, next.minutesUntil) * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale))
        return String(localized: "\(time) \(next.title) · in \(duration)", bundle: AppLocalization.bundle(for: locale), locale: locale)
    }

    private func taskRow(_ task: MuninnTask) -> some View {
        let bundle = AppLocalization.bundle(for: locale)
        let isCompleting = completing.contains(task.key)
        return HStack(spacing: 6) {
            Button {
                completing.insert(task.key)
                Task {
                    await service.complete(task)
                    completing.remove(task.key)
                }
            } label: {
                Image(systemName: isCompleting ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)
            .disabled(isCompleting)
            .help(String(localized: "Mark done (also in Google)", bundle: bundle, locale: locale))
            .accessibilityLabel(String(localized: "Mark done (also in Google)", bundle: bundle, locale: locale))

            Button {
                viewModel.focusTask = task.title
            } label: {
                Text(task.title)
                    .lineLimit(1)
                    .foregroundStyle(task.overdue ? Color.orange : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.overdue ? String(localized: "Past due — use as task", bundle: bundle, locale: locale)
                  : String(localized: "Use as task", bundle: bundle, locale: locale))

            Menu {
                Button(String(localized: "Use as task", bundle: bundle, locale: locale)) { viewModel.focusTask = task.title }
                Button(String(localized: "Set as today's mission", bundle: bundle, locale: locale)) { setMission(task.title) }
                    .disabled(!settings.transitionManagementEnabled)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.callout)
    }

    /// 오늘의 미션으로 삼기. 미션 칸에서 고친 것과 똑같이 노트에도 한 방향으로 적습니다.
    private func setMission(_ title: String) {
        let today = Date()
        settings.dailyMissions.setText(title, for: today)
        ObsidianExporter.shared.updateMission(settings.dailyMissions.mission(for: today), for: today)
    }
}

// MARK: - 집중 뒤 기분

struct MoodPicker: View {
    @Environment(\.locale) private var locale
    let selection: Int?
    let select: (Int) -> Void
    static let faces = ["😞", "🙁", "😐", "🙂", "😄"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("How did it go? (optional)").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Array(Self.faces.enumerated()), id: \.offset) { index, face in
                    let mood = index + 1
                    Button { select(mood) } label: {
                        Text(verbatim: face)
                            .font(.title3)
                            .padding(3)
                            .background(selection == mood ? Color.accentColor.opacity(0.25) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.moodName(mood, locale: locale))
                    .help(Self.moodName(mood, locale: locale))
                }
            }
        }
    }

    nonisolated static func moodName(_ mood: Int, locale: Locale = .current) -> String {
        let bundle = AppLocalization.bundle(for: locale)
        switch mood {
        case 1: return String(localized: "Very low", bundle: bundle, locale: locale)
        case 2: return String(localized: "Low", bundle: bundle, locale: locale)
        case 3: return String(localized: "Okay", bundle: bundle, locale: locale)
        case 4: return String(localized: "Good", bundle: bundle, locale: locale)
        default: return String(localized: "Great", bundle: bundle, locale: locale)
        }
    }
}
