//
//  StartFocusPromptTests.swift
//  MorrowispTests
//
//  집중 시작 제안(W1): 대기 중이고 오늘의 미션이 남아 있으면 팝오버에서 "이 미션으로 집중을 시작할까요?"를 한 줄 보여 줍니다.
//  누르면 기존 시작(startFocusSession)을 그대로 부르므로 타이머·단축어·기록은 시작 버튼과 같습니다.
//  알림·자동 시작·잠금은 없습니다.
//

import Foundation
import SwiftData
import Testing
@testable import Morrowisp

@MainActor
struct StartFocusPromptTests {

    private let startShortcut = "집중 시작"
    private let clock = TestClock()
    private let settings: AppSettings
    private let container: ModelContainer
    private let appDelegate = AppDelegate()
    private let recorder = ShortcutRecorder()
    private let viewModel: PomodoroViewModel

    init() throws {
        let settings = AppSettings(defaults: nil)
        settings.notificationSoundName = AppSettings.soundOff
        settings.focusStartShortcut = startShortcut
        self.settings = settings
        container = try ModelContainer(
            for: FocusLogEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let clock = self.clock
        viewModel = PomodoroViewModel(
            modelContext: container.mainContext,
            appDelegate: appDelegate,
            settings: settings,
            shortcuts: recorder,
            now: { clock.date }
        )
    }

    private func setTodayMission(_ text: String) {
        settings.dailyMissions.setText(text, for: clock.date)
    }

    @Test func 대기_중이고_오늘_미션이_남았으면_제안한다() {
        #expect(viewModel.focusPromptMission == nil, "미션이 없으면 제안하지 않는다")
        setTodayMission("  서론 교정  ")
        #expect(viewModel.focusPromptMission == "서론 교정")
    }

    @Test func 제안으로_시작하면_빈_할_일에_미션을_넣고_집중이_한_번만_시작된다() {
        setTodayMission("서론 교정")
        viewModel.startFocusFromPrompt()

        #expect(viewModel.currentState == .focus)
        #expect(viewModel.timerState == .running)
        #expect(viewModel.focusTask == "서론 교정")
        #expect(recorder.names == [startShortcut], "시작 단축어는 시작 버튼과 같이 한 번만")
        #expect(viewModel.focusPromptMission == nil, "집중 중에는 제안하지 않는다")

        // 다시 눌러도 두 번째 타이머나 단축어가 생기지 않는다
        viewModel.startFocusFromPrompt()
        viewModel.startFocusSession()
        #expect(recorder.names == [startShortcut])
        let full = TimeInterval(settings.focusDurationInMinutes * 60)
        clock.advance(60)
        viewModel.tick()
        #expect(abs(viewModel.timeRemaining - (full - 60)) < 0.5)
    }

    @Test func 이미_적은_할_일은_덮어쓰지_않는다() {
        viewModel.focusTask = "참고문헌 정리"
        setTodayMission("서론 교정")
        viewModel.startFocusFromPrompt()
        #expect(viewModel.focusTask == "참고문헌 정리")
        #expect(viewModel.currentState == .focus)
    }

    @Test func 끝낸_미션이나_전환_관리_꺼짐에서는_제안하지_않는다() {
        setTodayMission("서론 교정")
        settings.dailyMissions.toggleDone(for: clock.date)
        #expect(viewModel.focusPromptMission == nil, "끝낸 미션")

        settings.dailyMissions.toggleDone(for: clock.date)
        settings.transitionManagementEnabled = false
        #expect(viewModel.focusPromptMission == nil, "전환 관리 꺼짐")
        viewModel.startFocusFromPrompt()
        #expect(viewModel.timerState == .idle, "제안이 없으면 눌러도 시작하지 않는다")
        #expect(recorder.names.isEmpty)
    }

    @Test func 미션을_지우면_제안이_사라지고_다시_적으면_돌아온다() {
        setTodayMission("서론 교정")
        setTodayMission("")
        #expect(viewModel.focusPromptMission == nil)
        setTodayMission("결론 교정")
        #expect(viewModel.focusPromptMission == "결론 교정")
    }

    @Test func 제안이_없을_때_누르면_할_일도_바뀌지_않는다() {
        viewModel.focusTask = "참고문헌 정리"
        setTodayMission("서론 교정")
        settings.transitionManagementEnabled = false
        viewModel.startFocusFromPrompt()
        #expect(viewModel.focusTask == "참고문헌 정리")
        viewModel.focusTask = ""
        viewModel.startFocusFromPrompt()
        #expect(viewModel.focusTask.isEmpty)
        #expect(viewModel.timerState == .idle)
    }

    @Test func 자정이_지나면_어제_미션은_제안하지_않는다() {
        setTodayMission("어제의 글")
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: clock.date))!
        clock.advance(midnight.timeIntervalSince(clock.date) + 1)
        #expect(viewModel.focusPromptMission == nil)
        viewModel.startFocusFromPrompt()
        #expect(viewModel.timerState == .idle)
    }

    @Test func 휴식_뒤_준비된_집중이나_휴식_중에는_제안하지_않는다() {
        // 대기(idle/idle)에서만 묻는다. 휴식 중의 돌아가기는 기존 "복귀"가 맡는다.
        setTodayMission("서론 교정")
        settings.autoStartBreaks = false
        viewModel.startFocusSession()
        clock.advance(60)
        viewModel.skipToNextSession()
        #expect(viewModel.currentState == .shortBreak)
        #expect(viewModel.timerState == .idle)
        #expect(viewModel.focusPromptMission == nil)
    }
}
