// File: AppDelegate.swift
// Description: 상태 표시줄 아이콘, 팝오버, 알림 등 AppKit 관련 기능을 관리합니다.

import Cocoa
import SwiftUI
import SwiftData
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    // 다른 앱 화면을 클릭했을 때 팝오버를 닫기 위한 전역 마우스 이벤트 모니터.
    // .transient 동작은 우리 앱 안의 클릭만 감지하므로, 로그 창 등 다른 윈도우가
    // 열려 있는 상태에서 외부 앱을 클릭하면 팝오버가 닫히지 않는 문제가 있습니다.
    private var popoverEventMonitor: Any?

    var modelContext: ModelContext?
    private var pomodoroViewModel: PomodoroViewModel!

    // 자동 업데이트. (테스트에서 다른 것으로 바꿔 끼울 수 있게 변수로 둡니다.)
    @MainActor lazy var updates: UpdateController = .shared

    // 앱 실행 초기 단계에서 중복 실행 체크
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 테스트 호스트로 실행된 경우에는 중복 실행 체크를 건너뜁니다.
        // (사용 중인 앱이 떠 있으면 테스트 호스트가 exit(0) 으로 꺼져 테스트가 시작도 못 합니다.)
        if DataController.isRunningTests { return }
        #if DEBUG
        if PreviewHarness.isActive { return }
        #endif
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if runningApps.count > 1 {
            // 기존 앱 활성화하고 새 인스턴스 즉시 종료
            for app in runningApps where app != NSRunningApplication.current {
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            // 즉시 종료 (exit 사용)
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if DataController.isRunningTests { return }
        #if DEBUG
        if PreviewHarness.isActive { MainActor.assumeIsolated { PreviewHarness.run() }; return }
        #endif
        guard let modelContext = modelContext else {
            fatalError("AppDelegate에 ModelContext가 제공되지 않았습니다.")
        }

        // ViewModel에 AppDelegate 참조를 전달하여 팝오버를 제어할 수 있도록 합니다.
        self.pomodoroViewModel = PomodoroViewModel(
            modelContext: modelContext,
            appDelegate: self,
            notesContext: DataController.shared.transitionContainer?.mainContext
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            let hostingView = NSHostingView(rootView: StatusBarView().environmentObject(pomodoroViewModel))
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.subviews.forEach { $0.removeFromSuperview() }
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor)
            ])
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let popoverController = NSHostingController(
            rootView: PopoverView()
               .environmentObject(pomodoroViewModel)
               .environment(\.modelContext, modelContext)
        )
        // 팝오버 크기는 내용을 따릅니다 (할 일·보상 칸과 선택 화면에 따라 높이가 달라집니다).
        popoverController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = popoverController

        UNUserNotificationCenter.current().delegate = self
        
        Task {
            await pomodoroViewModel.requestNotificationPermission()
        }

        // 자동 업데이트. 새 버전은 받아 두고 메뉴 막대 아이콘에 표시만 합니다 — 설치는 사용자가 누를 때 합니다.
        // (테스트 호스트와 개발 빌드에서는 켜지지 않습니다.)
        updates.start()
    }

    @objc func togglePopover(_ sender: AnyObject? = nil) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            Task {
                await pomodoroViewModel.checkNotificationSettings()
            }
            // 기록 창에서 메모를 지웠을 수 있으니, 칸 옆의 "지난 것에서 고르기"를 열 때마다 다시 읽습니다.
            MainActor.assumeIsolated { pomodoroViewModel.refreshNoteSuggestions() }
            // Muninn 오늘 할 일·일정 (60초 안에 다시 열면 부르지 않습니다). 실패해도 팝오버는 그대로 열립니다.
            Task { await MuninnService.shared.refresh() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            startPopoverEventMonitor()
        }
    }

    // 전역 모니터는 다른 앱에서 발생한 이벤트만 전달받으므로,
    // 외부 앱 클릭 시 팝오버를 닫는 용도로 정확히 들어맞습니다.
    private func startPopoverEventMonitor() {
        guard popoverEventMonitor == nil else { return }
        popoverEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func stopPopoverEventMonitor() {
        if let monitor = popoverEventMonitor {
            NSEvent.removeMonitor(monitor)
            popoverEventMonitor = nil
        }
    }

    // transient 동작 등 어떤 경로로 닫히든 모니터를 함께 해제합니다.
    func popoverDidClose(_ notification: Notification) {
        stopPopoverEventMonitor()
    }
    
    // 토글과 달리 이미 닫혀 있으면 다시 열지 않습니다.
    // performClose()는 다른 윈도우가 키를 가져간 직후에는 무시될 수 있어
    // (예: 이미 열린 로그 창을 다시 앞으로 가져온 경우) close()로 강제로 닫습니다.
    public func closePopover() {
        if popover.isShown {
            popover.close()
        }
        stopPopoverEventMonitor()
    }

    // 세션 종료 시 팝오버를 앞으로 가져오는 public 메서드
    public func bringPopoverToFront() {
        if !popover.isShown {
            togglePopover()
        } else {
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // 앱이 활성화된 상태에서도 알림이 보이도록 설정합니다.
    // .list 제거: 알림 센터에 저장하지 않아 클릭할 수 없게 함
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // 알림 클릭 시 아무 동작도 하지 않음 (새 앱 인스턴스 실행 방지)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // 아무것도 하지 않고 완료 처리
        completionHandler()
    }

    // 마지막 윈도우가 닫혀도 앱이 종료되지 않도록 합니다 (메뉴 바 앱)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // 종료하기 전에 진행 중인 세션을 기록합니다. 집중 도중이었고 끝 단축어(방해금지 끄기 등)가 있으면
    // 그 실행 요청이 넘어갈 때까지 종료를 잠깐 미룹니다. 요청은 비동기라, 바로 끝내면 전달되기 전에
    // 프로세스가 사라질 수 있습니다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let pomodoroViewModel else { return .terminateNow }
        var finished = false
        var shouldReply = false // .terminateLater 를 돌려준 뒤에만 답합니다
        let finish = {
            guard !finished else { return }
            finished = true
            if shouldReply { sender.reply(toApplicationShouldTerminate: true) }
        }
        guard pomodoroViewModel.logInterruptedSession(shortcutDelivered: finish), !finished else {
            return .terminateNow
        }
        shouldReply = true
        // 단축어 앱이 응답하지 않아도 종료가 멈춰 있지 않도록 2초 뒤에는 끝냅니다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: finish)
        return .terminateLater
    }

    // 앱 종료 시 (위에서 이미 기록하지 못한 경우에 대비해) 진행 중인 세션을 기록하고 알림 취소
    func applicationWillTerminate(_ notification: Notification) {
        pomodoroViewModel?.logInterruptedSession()
        pomodoroViewModel?.cancelAllNotifications()
    }
}
