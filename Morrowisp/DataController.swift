// File: DataController.swift
// Description: SwiftData ModelContainer를 관리하는 싱글턴 클래스입니다.
// 앱의 모든 부분에서 동일한 데이터베이스 컨텍스트에 안전하게 접근할 수 있도록 보장합니다.

import Foundation
import SwiftData

class DataController {
    static let shared = DataController()

    lazy var container: ModelContainer = {
        do {
            // 단위 테스트의 호스트로 실행될 때는 실제 기록 저장소를 열지 않습니다.
            // (테스트가 사용자의 집중 기록을 읽거나 바꾸지 않도록 메모리 저장소를 씁니다.)
            if DataController.usesMemoryStores {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: FocusLogEntry.self, configurations: config)
            }
            // FocusLogEntry 모델에 대한 컨테이너를 생성합니다.
            let container = try ModelContainer(for: FocusLogEntry.self)
            return container
        } catch {
            fatalError("SwiftData 컨테이너 생성에 실패했습니다: \(error.localizedDescription)")
        }
    }()

    /// 할 일·보상·다음 시작점(TransitionNote)을 두는 별도 저장소.
    /// 집중 기록 저장소와 파일이 달라서, 이 기능이 없는 빌드로 돌아가도 기록은 그대로 열립니다.
    /// 열지 못하면 nil 이고, 그때는 메모만 저장되지 않습니다(타이머와 기록은 그대로 동작).
    lazy var transitionContainer: ModelContainer? = {
        do {
            if DataController.usesMemoryStores {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: TransitionNote.self, configurations: config)
            }
            let folder = URL.applicationSupportDirectory
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let config = ModelConfiguration(url: folder.appending(path: "Transitions.store"))
            return try ModelContainer(for: TransitionNote.self, configurations: config)
        } catch {
            print("전환 메모 저장소를 열지 못했습니다: \(error)")
            return nil
        }
    }()

    /// xcodebuild test 가 앱을 테스트 호스트로 띄웠는지 여부.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// 메모리 저장소를 쓸지: 테스트 호스트이거나, 개발 빌드의 화면 찍기(PreviewHarness)일 때.
    static var usesMemoryStores: Bool {
        #if DEBUG
        if PreviewHarness.isActive { return true }
        #endif
        return isRunningTests
    }

    private init() {}
}
