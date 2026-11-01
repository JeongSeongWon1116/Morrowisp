// File: PopoverView.swift
// Description: 메뉴 바 아이콘 클릭 시 표시되는 팝오버 UI입니다.
// 타이머 제어에 집중하고, 상세 설정은 별도의 설정 창에서 합니다.

import SwiftUI
import SwiftData

struct PopoverView: View {
    @Environment(\.locale) private var locale
    var notesContext: ModelContext? = DataController.shared.transitionContainer?.mainContext
    @EnvironmentObject var viewModel: PomodoroViewModel
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var updates = UpdateController.shared
    @ObservedObject var muninn = MuninnService.shared
    @Environment(\.openWindow) private var openWindow

    private var isAwaitingChoice: Bool { viewModel.timerState == .awaitingChoice }

    var body: some View {
        VStack(spacing: 12) {
            if settings.transitionManagementEnabled {
                DailyMissionView(store: settings.dailyMissions)
            }

            // 세로로 길어지지 않게 두 칸으로: 왼쪽은 타이머와 조작, 오른쪽은 할 일·보상·제안.
            HStack(alignment: .top, spacing: 16) {
                timerColumn
                    .frame(width: 190)
                if hasSideColumn {
                    sideColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            HStack {
                Button("View history") {
                    viewModel.closePopover()
                    openWindow(id: "log-window")
                }
                Spacer()
                Button {
                    viewModel.closePopover()
                    openWindow(id: "settings-window")
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Spacer()
                Button("Quit") {
                    // 진행 중인 세션은 종료 과정(AppDelegate.applicationShouldTerminate)에서 기록합니다.
                    NSApplication.shared.terminate(nil)
                }
            }

            // 새 버전이 있을 때만 보이는 한 줄. 메뉴 막대 아이콘의 점과 짝입니다.
            if let version = updates.indicatedVersion {
                UpdateRow(
                    version: version,
                    downloaded: updates.pendingVersion != nil,
                    installing: updates.installInProgress
                ) {
                    viewModel.closePopover()
                    updates.performIndicatedUpdate()
                }
            }
        }
        .padding()
        // 높이는 내용(할 일·보상 칸, 선택 화면)에 맞춰 달라집니다.
        .frame(width: hasSideColumn ? 440 : 240)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hasSideColumn: Bool { settings.transitionManagementEnabled || isAwaitingChoice || muninn.isConfigured }

    /// 왼쪽 칸: 상태, 남은 시간, 주기 점, 시작·일시정지, 복귀·연장, 건너뛰기·초기화.
    private var timerColumn: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: isAwaitingChoice ? "bell.badge" : viewModel.currentState.symbolName)
                    .foregroundStyle(viewModel.currentState.color)
                Text(isAwaitingChoice ? String(localized: "\(viewModel.currentState.localizedDescription(locale: locale)) ended", bundle: AppLocalization.bundle(for: locale), locale: locale) : viewModel.currentState.localizedDescription(locale: locale))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.headline)

            Text(viewModel.timeRemainingString)
                .font(.system(size: 40, weight: .light, design: .rounded))
                .monospacedDigit()

            CycleDotsView(
                completed: viewModel.focusSessionsInCurrentCycle,
                total: settings.longBreakInterval
            )

            Button(action: primaryAction) {
                Text(buttonTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)

            if isAwaitingChoice {
                Button("Focus for \(Int(PomodoroViewModel.focusExtension / 60).formatted()) more min") { viewModel.extendFocus() }
                    .frame(maxWidth: .infinity)
            }

            // 휴식 중: 다시 계획하지 않고 하던 일로 바로 돌아간다 (휴식은 지금까지로 기록)
            if viewModel.canReturnToFocus {
                Button("Return — start focusing") { viewModel.returnToFocus() }
                    .frame(maxWidth: .infinity)
                    .help("End this break and start focusing with your task and next starting point")
            }

            HStack {
                Button("Skip") { viewModel.skipToNextSession() }
                    .disabled(viewModel.timerState == .idle || isAwaitingChoice)
                Spacer()
                Button("Reset") { viewModel.resetToIdle() }
                    .disabled(viewModel.timerState == .idle && viewModel.currentState == .idle)
            }
        }
    }

    /// 오른쪽 칸: 집중 시작 제안, 할 일·보상·다음 시작점, 오늘 요약.
    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            if muninn.isConfigured && !isAwaitingChoice {
                MuninnTodaySection(service: muninn)
            }
            if settings.transitionManagementEnabled {
                FocusPromptRow(store: settings.dailyMissions)
            }
            transitionNotes
            Spacer(minLength: 0)
            if settings.transitionManagementEnabled {
                DaySummaryView(notesContext: notesContext, completions: settings.focusCompletions,
                               isFocusing: viewModel.currentState == .focus)
            }
        }
    }

    /// 할 일·보상·다음 시작점. 집중 전과 집중 중에는 적는 칸, 집중이 끝나면 보상과 다음 시작점 칸, 휴식 중에는 읽기만.
    @ViewBuilder
    private var transitionNotes: some View {
        let reward = viewModel.focusReward.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 6) {
            if isAwaitingChoice {
                if !reward.isEmpty { NoteLine(label: String(localized: "Reward", bundle: AppLocalization.bundle(for: locale), locale: locale), text: reward) }
                TextField("Where to pick up next time", text: $viewModel.nextStartingPoint)
                    .textFieldStyle(.roundedBorder)
                // 기분은 Muninn 하루 기록에만 붙으므로, 연결했을 때만 묻습니다. 건너뛰어도 됩니다.
                if muninn.isConfigured {
                    MoodPicker(selection: viewModel.focusMood) { viewModel.setMood($0) }
                }
            } else if viewModel.currentState == .idle || viewModel.currentState == .focus {
                if !viewModel.resumeHint.isEmpty { NoteLine(label: String(localized: "Pick up from", bundle: AppLocalization.bundle(for: locale), locale: locale), text: viewModel.resumeHint) }
                NoteField(title: String(localized: "Task", bundle: AppLocalization.bundle(for: locale), locale: locale), text: $viewModel.focusTask,
                          suggestions: viewModel.taskSuggestions, help: String(localized: "Choose from past tasks", bundle: AppLocalization.bundle(for: locale), locale: locale))
                RewardField(store: settings.rewardList, text: $viewModel.focusReward,
                            suggestions: viewModel.rewardSuggestions)
            } else {
                if let suggestion = viewModel.localizedBreakSuggestion(locale: locale) { NoteLine(label: String(localized: "Suggestion", bundle: AppLocalization.bundle(for: locale), locale: locale), text: suggestion) }
                if !reward.isEmpty { NoteLine(label: String(localized: "Reward", bundle: AppLocalization.bundle(for: locale), locale: locale), text: reward) }
                let task = viewModel.focusTask.trimmingCharacters(in: .whitespacesAndNewlines)
                if !task.isEmpty { NoteLine(label: String(localized: "Your task", bundle: AppLocalization.bundle(for: locale), locale: locale), text: task) }
                if !viewModel.resumeHint.isEmpty { NoteLine(label: String(localized: "Next starting point", bundle: AppLocalization.bundle(for: locale), locale: locale), text: viewModel.resumeHint) }
            }
        }
    }

    private func primaryAction() {
        switch viewModel.timerState {
        case .idle: viewModel.startFocusSession()
        case .paused: viewModel.resumeTimer()
        case .running: viewModel.pauseTimer()
        case .awaitingChoice: viewModel.startBreakAfterFocus()
        }
    }

    private var buttonTitle: String {
        switch viewModel.timerState {
        case .running: String(localized: "Pause", bundle: AppLocalization.bundle(for: locale), locale: locale)
        case .paused: String(localized: "Resume", bundle: AppLocalization.bundle(for: locale), locale: locale)
        case .idle: viewModel.currentState == .idle ? String(localized: "Start", bundle: AppLocalization.bundle(for: locale), locale: locale) : String(localized: "Start \(viewModel.currentState.localizedDescription(locale: locale))", bundle: AppLocalization.bundle(for: locale), locale: locale)
        case .awaitingChoice: String(localized: "Start break", bundle: AppLocalization.bundle(for: locale), locale: locale)
        }
    }

}

/// 집중 시작 제안: 대기 중이고 오늘의 미션이 남았을 때만 보이는 한 줄. 누르면 시작 버튼과 같은 시작을 부릅니다.
/// 미션을 고치거나 자정이 지나면 다시 그리도록 미션 저장소와 분 단위 시계를 봅니다.
struct FocusPromptRow: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject var viewModel: PomodoroViewModel
    @ObservedObject var store: DailyMissionStore

    var body: some View {
        // 분 단위 시계: 팝오버가 열린 채 자정을 지나면 어제 미션의 제안을 거둡니다. 지우지 마세요.
        TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 60)) { _ in
            if let mission = viewModel.focusPromptMission {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Start focusing on this?", bundle: AppLocalization.bundle(for: locale), locale: locale))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(mission).font(.callout).lineLimit(2)
                        Spacer(minLength: 4)
                        Button(String(localized: "Start focus", bundle: AppLocalization.bundle(for: locale), locale: locale)) {
                            viewModel.startFocusFromPrompt()
                        }
                        .controlSize(.small)
                        .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 팝오버 맨 아래의 "새 버전" 줄. 상태를 값으로 받아, 업데이터 없이도 그려 볼 수 있습니다.
struct UpdateRow: View {
    @Environment(\.locale) private var locale
    let version: String
    /// 받아 두었는지. 받아 두었으면 누르자마자 설치하고 앱이 다시 켜집니다. 아니면 Sparkle 의 안내 창이 뜹니다.
    let downloaded: Bool
    /// 설치를 시작해 앱이 꺼지기를 기다리는 중인지
    let installing: Bool
    let update: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            UpdateDot()
            Text("New version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("New version \(version)")
            Spacer()
            Button(Self.buttonTitle(installing: installing, locale: locale), action: update)
                .controlSize(.small)
                .fixedSize()
                .disabled(installing)
                .help(Self.help(downloaded: downloaded, locale: locale))
        }
    }

    nonisolated static func buttonTitle(installing: Bool, locale: Locale = .current) -> String {
        installing ? String(localized: "Installing…", bundle: AppLocalization.bundle(for: locale), locale: locale) : String(localized: "Update", bundle: AppLocalization.bundle(for: locale), locale: locale)
    }

    /// 누르면 무슨 일이 일어나는지. 받아 둔 것은 곧바로 앱을 껐다 켜므로 그렇게 적습니다.
    nonisolated static func help(downloaded: Bool, locale: Locale = .current) -> String {
        downloaded ? String(localized: "Install and reopen the app", bundle: AppLocalization.bundle(for: locale), locale: locale) : String(localized: "Open the new version window", bundle: AppLocalization.bundle(for: locale), locale: locale)
    }
}

/// 글을 적는 칸. 지난 집중에 적었던 글이 있으면 칸 옆의 단추로 골라 넣을 수 있습니다.
struct NoteField: View {
    @Environment(\.locale) private var locale
    let title: String
    @Binding var text: String
    let suggestions: [String]
    let help: String
    var rewards: [RewardItem] = []
    @FocusState private var isEditing: Bool

    var body: some View {
        let menu = NoteFieldMenu.make(rewards: rewards, suggestions: suggestions)
        HStack(spacing: 4) {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isEditing)
            if menu.isVisible {
                Menu {
                    ForEach(menu.groups) { group in
                        Section(group.size.localizedTitle(locale: locale)) {
                            ForEach(group.items) { item in
                                Button(Self.menuTitle(item.name)) { pick(item.name) }
                            }
                        }
                    }
                    if menu.showsHistoryDivider {
                        Divider()
                        Text(RewardListText(locale: locale).history)
                    }
                    ForEach(menu.suggestions, id: \.self) { suggestion in
                        Button(Self.menuTitle(suggestion)) { pick(suggestion) }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(help)
                .accessibilityLabel(help)
            }
        }
    }

    private func pick(_ suggestion: String) {
        // 이 칸을 편집하던 중이면 편집을 끝내고(다른 칸과 다른 창은 건드리지 않습니다) 고른 글을 넣습니다.
        isEditing = false
        text = suggestion
        // 편집을 끝내는 처리나 입력기의 확정이 뒤늦게 돌아 적던 글이 다시 들어오면, 고른 글을 한 번 더 넣습니다.
        let text = $text
        DispatchQueue.main.async {
            if text.wrappedValue != suggestion { text.wrappedValue = suggestion }
        }
    }

    /// 메뉴에는 한 줄로, 길면 줄여서 보여 줍니다 (고르면 원래 글이 그대로 들어갑니다).
    nonisolated static func menuTitle(_ text: String, limit: Int = 30) -> String {
        let oneLine = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return oneLine.count > limit ? oneLine.prefix(limit) + "…" : oneLine
    }
}

/// "보상: 커피" 처럼 적어 둔 글을 한두 줄로 보여 줍니다.
struct NoteLine: View {
    let label: String
    let text: String

    var body: some View {
        Text(verbatim: "\(label): \(text)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 긴 휴식까지 남은 집중 사이클을 점으로 표시합니다.
struct CycleDotsView: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(1, total), id: \.self) { index in
                Circle()
                    .fill(index < completed ? PomodoroState.focus.color : Color.primary.opacity(0.15))
                    .frame(width: 8, height: 8)
            }
        }
        .help("Focus sessions leading to a long break")
    }
}
