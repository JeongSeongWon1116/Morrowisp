// File: PreviewHarness.swift
// Description: 개발 빌드 전용 화면 찍기. 릴리스 빌드에는 들어가지 않습니다 (#if DEBUG).
// MORROWISP_PREVIEW_DIR 가 있을 때만 켜지고, 기록은 메모리에만 두며 키체인을 쓰지 않습니다.
// 장면 하나를 그려 PNG 로 저장하고 앱을 끕니다.

#if DEBUG
import AppKit
import SwiftUI
import SwiftData

@MainActor
enum PreviewHarness {
    nonisolated static var environment: [String: String] { ProcessInfo.processInfo.environment }
    nonisolated static var isActive: Bool { environment["MORROWISP_PREVIEW_DIR"] != nil }

    final class Clock { var date = Date() }
    private static var window: NSWindow?
    private static var keepAlive: [AnyObject] = []

    /// MORROWISP_PREVIEW_SCENE: popover | focus-end | settings-<section>
    static func run() {
        let env = environment
        let scene = env["MORROWISP_PREVIEW_SCENE"] ?? "popover"
        let out = URL(fileURLWithPath: env["MORROWISP_PREVIEW_DIR"]!)
            .appending(path: env["MORROWISP_PREVIEW_NAME"] ?? scene).appendingPathExtension("png")

        let settings = AppSettings.shared // 미리 보기에서는 저장하지 않는 설정 (AppSettings.shared 참고)
        settings.notificationSoundName = AppSettings.soundOff
        if let mission = env["MORROWISP_PREVIEW_MISSION"] { settings.dailyMissions.setText(mission, for: Date()) }
        let container = try! ModelContainer(for: FocusLogEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let clock = Clock()
        let delegate = AppDelegate()
        let viewModel = PomodoroViewModel(modelContext: container.mainContext, appDelegate: delegate, settings: settings,
                                          notesContext: DataController.shared.transitionContainer?.mainContext,
                                          shortcuts: NoShortcuts(), recordFocusJournal: { _, _ in }, exportSession: { _, _ in },
                                          now: { clock.date })
        keepAlive = [container, delegate, viewModel, clock]
        if let task = env["MORROWISP_PREVIEW_TASK"] { viewModel.focusTask = task }

        let root: AnyView
        let size: NSSize
        if scene.hasPrefix("settings-") {
            // 설정 칸 기억은 미리 보기 전용 저장소에 (사용자의 설정 파일은 건드리지 않음)
            let storage = UserDefaults(suiteName: "dev.swsquare.morrowisp.preview-harness")!
            storage.set(String(scene.dropFirst("settings-".count)), forKey: "settingsSection")
            root = AnyView(PreferencesView().defaultAppStorage(storage))
            size = NSSize(width: 720, height: 500)
        } else {
            if scene == "focus-end" {
                viewModel.startFocusSession()
                clock.date = clock.date.addingTimeInterval(viewModel.timeRemaining)
                viewModel.tick()
                viewModel.setMood(4)
            }
            root = AnyView(PopoverView(notesContext: DataController.shared.transitionContainer?.mainContext)
                .environmentObject(viewModel)
                .background(Color(nsColor: .windowBackgroundColor)))
            size = NSSize(width: 440, height: 400)
        }

        let controller = NSHostingController(rootView: root)
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = scene.hasPrefix("settings-") ? [.titled, .closable, .miniaturizable] : [.borderless]
        window.title = scene.hasPrefix("settings-") ? String(localized: "Settings") : "Morrowisp"
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: 120, y: 120))
        Self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Task {
            await MuninnService.shared.refresh(force: true)
            try? await Task.sleep(for: .seconds(2))
            if !scene.hasPrefix("settings-") {
                let fitted = controller.view.fittingSize
                if fitted.height > 0 { window.setContentSize(NSSize(width: max(fitted.width, 240), height: fitted.height)) }
            }
            try? await Task.sleep(for: .milliseconds(800))
            // 찍기는 바깥에서 이 창 번호로만 합니다 (screencapture -l). 다른 화면은 찍지 않습니다.
            try? "\(window.windowNumber)".write(to: out.deletingPathExtension().appendingPathExtension("window"), atomically: true, encoding: .utf8)
            try? await Task.sleep(for: .seconds(4))
            NSApp.terminate(nil)
        }
    }

    private final class NoShortcuts: ShortcutRunning {
        func run(named name: String, completion: (() -> Void)?) {}
    }
}

/// 미리 보기에서 쓰는 토큰 보관: 환경 변수 값만 메모리에 둡니다. 키체인은 건드리지 않습니다.
final class PreviewTokenStore: MuninnTokenStoring {
    private var token: String?
    init(_ token: String?) { self.token = token }
    func read() -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() { token = nil }
}
#endif
