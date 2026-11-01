// File: AppSettings.swift
// Description: 모든 사용자 설정을 한곳에서 관리하는 싱글턴입니다.
// 팝오버, 설정 창, ViewModel이 같은 인스턴스를 관찰하여 항상 동기화됩니다.

import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared: AppSettings = {
        #if DEBUG
        // 개발 빌드의 화면 찍기는 사용자의 설정을 읽거나 쓰지 않습니다.
        if PreviewHarness.isActive { return AppSettings(defaults: nil) }
        #endif
        return AppSettings()
    }()

    static let soundOff = "없음"
    // NSSound(named:)로 재생 가능한 macOS 시스템 알림음 목록
    static let availableSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    @Published var focusDurationInMinutes: Int {
        didSet { defaults?.set(focusDurationInMinutes, forKey: "focusDuration") }
    }
    @Published var shortBreakDurationInMinutes: Int {
        didSet { defaults?.set(shortBreakDurationInMinutes, forKey: "shortBreakDuration") }
    }
    @Published var longBreakDurationInMinutes: Int {
        didSet { defaults?.set(longBreakDurationInMinutes, forKey: "longBreakDuration") }
    }
    @Published var longBreakInterval: Int {
        didSet { defaults?.set(longBreakInterval, forKey: "longBreakInterval") }
    }

    /// 집중이 끝났을 때 휴식을 자동으로 시작할지 여부
    @Published var autoStartBreaks: Bool {
        didSet { defaults?.set(autoStartBreaks, forKey: "autoStartBreaks") }
    }
    /// 휴식이 끝났을 때 집중을 자동으로 시작할지 여부
    @Published var autoStartFocus: Bool {
        didSet { defaults?.set(autoStartFocus, forKey: "autoStartFocus") }
    }

    /// 전환 관리(할 일·보상·다음 시작점 적기, 집중이 끝났을 때 선택 기다리기)를 쓸지 여부.
    /// 끄면 칸도 선택 화면도 없이 예전처럼 동작하고, 메모도 남기지 않습니다.
    @Published var transitionManagementEnabled: Bool {
        didSet { defaults?.set(transitionManagementEnabled, forKey: "transitionManagementEnabled") }
    }

    /// 집중을 시작할 때와 집중이 끝날 때 실행할 단축어의 이름. 비워 두면 실행하지 않습니다.
    @Published var focusStartShortcut: String {
        didSet { defaults?.set(focusStartShortcut, forKey: "focusStartShortcut") }
    }
    @Published var focusEndShortcut: String {
        didSet { defaults?.set(focusEndShortcut, forKey: "focusEndShortcut") }
    }

    @Published var notificationSoundName: String {
        didSet { defaults?.set(notificationSoundName, forKey: "notificationSound") }
    }

    /// 메뉴 바에 남은 시간을 텍스트로 표시할지 여부
    @Published var showTimeInMenuBar: Bool {
        didSet { defaults?.set(showTimeInMenuBar, forKey: "showTimeInMenuBar") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("로그인 시 자동 실행 설정 실패: \(error)")
            }
        }
    }

    /// 긴 휴식 간격으로 쓸 수 있는 값으로 고칩니다.
    /// (0 이나 음수가 저장돼 있으면 나머지 연산에서 앱이 죽으므로 최소 1로 맞춥니다.)
    static func validLongBreakInterval(_ value: Int) -> Int {
        max(1, value)
    }

    // 저장소. nil 이면 기본값만 쓰고 아무것도 저장하지 않습니다(단위 테스트용).
    // ViewModel 도 적어 둔 할 일·보상을 여기에 둡니다.
    let defaults: UserDefaults?
    let dailyMissions: DailyMissionStore
    let rewardList: RewardListStore
    let focusCompletions: FocusCompletionStore
    let weeklyReview: WeeklyReviewStore

    init(defaults: UserDefaults? = .standard, locale: Locale = .current) {
        self.defaults = defaults
        self.dailyMissions = DailyMissionStore(defaults: defaults)
        self.rewardList = RewardListStore(defaults: defaults, locale: locale)
        self.focusCompletions = FocusCompletionStore(defaults: defaults)
        self.weeklyReview = WeeklyReviewStore(defaults: defaults)
        self.focusDurationInMinutes = (defaults?.object(forKey: "focusDuration") as? Int) ?? 25
        self.shortBreakDurationInMinutes = (defaults?.object(forKey: "shortBreakDuration") as? Int) ?? 5
        self.longBreakDurationInMinutes = (defaults?.object(forKey: "longBreakDuration") as? Int) ?? 15
        self.longBreakInterval = Self.validLongBreakInterval((defaults?.object(forKey: "longBreakInterval") as? Int) ?? 4)
        self.autoStartBreaks = (defaults?.object(forKey: "autoStartBreaks") as? Bool) ?? true
        self.autoStartFocus = (defaults?.object(forKey: "autoStartFocus") as? Bool) ?? true
        self.transitionManagementEnabled = (defaults?.object(forKey: "transitionManagementEnabled") as? Bool) ?? true
        self.focusStartShortcut = defaults?.string(forKey: "focusStartShortcut") ?? ""
        self.focusEndShortcut = defaults?.string(forKey: "focusEndShortcut") ?? ""
        self.notificationSoundName = defaults?.string(forKey: "notificationSound") ?? "Glass"
        self.showTimeInMenuBar = (defaults?.object(forKey: "showTimeInMenuBar") as? Bool) ?? true
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
