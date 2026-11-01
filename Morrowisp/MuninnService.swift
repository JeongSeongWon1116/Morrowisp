// File: MuninnService.swift
// Description: Muninn 연결 상태, 오늘 할 일·다음 일정, 하루 기록 대기열.
// 무엇이 실패해도 타이머는 멈추지 않습니다. 팝오버에는 조용한 한 줄만 보입니다.

import Foundation
import Combine

@MainActor
final class MuninnService: ObservableObject {
    /// 단위 테스트 호스트에서는 사용자의 설정·키체인을 읽지 않습니다.
    static let shared: MuninnService = {
        if DataController.isRunningTests { return MuninnService(defaults: nil, tokens: EmptyTokenStore()) }
        #if DEBUG
        if PreviewHarness.isActive {
            let env = PreviewHarness.environment
            let service = MuninnService(defaults: nil, tokens: PreviewTokenStore(env["MORROWISP_PREVIEW_TOKEN"]))
            service.baseURLString = env["MORROWISP_PREVIEW_MUNINN"] ?? ""
            return service
        }
        #endif
        return MuninnService(defaults: .standard, tokens: KeychainTokenStore())
    }()

    enum Status: Equatable {
        case notConfigured, notLoaded, loaded, googleDisconnected, unreachable, unauthorized
    }

    struct NextEvent: Equatable {
        let title: String
        let start: Date
        let minutesUntil: Int
    }

    struct ShortFocusOffer: Equatable {
        let eventTitle: String
        let minutesUntil: Int
        let focusMinutes: Int
    }

    private static let baseURLKey = "muninnBaseURL"
    private static let queueKey = "muninnJournalQueue.v1"
    static let refreshInterval: TimeInterval = 60
    /// 다음 일정까지 이보다 덜 남았으면 짧은 집중을 제안합니다.
    static let shortFocusThreshold = 25
    private static let queueLimit = 100

    @Published var baseURLString: String {
        didSet {
            defaults?.set(baseURLString, forKey: Self.baseURLKey)
            resetLoadedState()
        }
    }
    @Published private(set) var hasToken: Bool
    @Published private(set) var today: MuninnToday?
    @Published private(set) var status: Status = .notLoaded
    /// 끝냄처럼 사용자가 누른 일이 서버에 닿지 않았는지 (다음 새로 고침에서 지웁니다)
    @Published private(set) var actionFailed = false
    @Published private(set) var pendingJournalCount = 0

    private struct PendingEntry: Codable { var id = UUID(); let day: String; let entry: JournalEntry }

    private let defaults: UserDefaults?
    private let tokens: MuninnTokenStoring
    private let session: URLSession
    private let now: () -> Date
    private var lastFetch: Date?
    /// 키체인은 처음 한 번만 읽고 여기 둡니다 (화면을 그릴 때마다 읽지 않게).
    private var token: String?
    /// 주소나 토큰을 바꾸면 올라갑니다. 그 전에 떠난 요청의 답은 버립니다.
    private var generation = 0
    private var isRefreshing = false
    private var isFlushing = false
    private var queue: [PendingEntry] {
        didSet {
            pendingJournalCount = queue.count
            if let data = try? JSONEncoder().encode(queue) { defaults?.set(data, forKey: Self.queueKey) }
        }
    }

    init(defaults: UserDefaults?, tokens: MuninnTokenStoring, session: URLSession? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.tokens = tokens
        self.session = session ?? {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 20
            config.waitsForConnectivity = false
            return URLSession(configuration: config)
        }()
        self.now = now
        baseURLString = defaults?.string(forKey: Self.baseURLKey) ?? ""
        token = tokens.read()
        hasToken = !(token ?? "").isEmpty
        queue = defaults?.data(forKey: Self.queueKey)
            .flatMap { try? JSONDecoder().decode([PendingEntry].self, from: $0) } ?? []
        pendingJournalCount = queue.count
        status = isConfigured ? .notLoaded : .notConfigured
    }

    // MARK: 연결

    var isConfigured: Bool { client != nil }

    private var client: MuninnClient? {
        guard let url = MuninnClient.validatedBaseURL(baseURLString),
              let token, !token.isEmpty else { return nil }
        return MuninnClient(baseURL: url, token: token, session: session)
    }

    func saveToken(_ text: String) throws {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        try tokens.save(token)
        self.token = token
        hasToken = true
        resetLoadedState()
    }

    func removeToken() {
        tokens.delete()
        token = nil
        hasToken = false
        resetLoadedState()
    }

    private func resetLoadedState() {
        generation += 1
        isRefreshing = false
        today = nil
        lastFetch = nil
        actionFailed = false
        status = isConfigured ? .notLoaded : .notConfigured
    }

    /// 설정의 "연결 확인". 성공하면 토큰 이름을 돌려줍니다.
    func testConnection() async -> Result<String, MuninnError> {
        guard let client else { return .failure(.unauthorized) }
        do {
            let name = try await client.whoami()
            await flushJournal()
            return .success(name)
        } catch let error as MuninnError {
            return .failure(error)
        } catch {
            return .failure(.unreachable)
        }
    }

    // MARK: 오늘

    /// 팝오버를 열 때와 열려 있는 동안 부릅니다. 60초 안에 다시 부르면 아무것도 하지 않습니다.
    func refresh(force: Bool = false) async {
        guard let client else { status = .notConfigured; today = nil; return }
        if isRefreshing { return }
        if !force, let lastFetch, now().timeIntervalSince(lastFetch) < Self.refreshInterval { return }
        isRefreshing = true
        lastFetch = now()
        let started = generation
        let result: Result<MuninnToday, Error>
        do { result = .success(try await client.today()) } catch { result = .failure(error) }
        guard started == generation else { return } // 그 사이 주소·토큰이 바뀜
        isRefreshing = false
        switch result {
        case .success(let today):
            self.today = today
            status = today.google == "disconnected" ? .googleDisconnected : .loaded
            actionFailed = false
        case .failure(MuninnError.unauthorized):
            status = .unauthorized
        case .failure:
            status = .unreachable
        }
        await flushJournal()
    }

    /// 지난 기한을 맨 위로. 같은 묶음 안에서는 서버가 준 순서를 지킵니다.
    var sortedTasks: [MuninnTask] {
        let tasks = today?.tasks ?? []
        return tasks.filter(\.overdue) + tasks.filter { !$0.overdue }
    }

    /// 아직 시작하지 않은 다음 일정 (시각이 있는 것만)
    var nextEvent: NextEvent? {
        guard let event = today?.nextEvent, let start = event.startDate else { return nil }
        let seconds = start.timeIntervalSince(now())
        guard seconds > 0 else { return nil }
        return NextEvent(title: event.title, start: start, minutesUntil: Int((seconds / 60).rounded(.down)))
    }

    /// normalMinutes: 설정의 집중 길이. 평소 집중이 이미 일정 전에 끝나면 따로 제안하지 않습니다.
    func shortFocusOffer(normalMinutes: Int) -> ShortFocusOffer? {
        guard let next = nextEvent, let minutes = Self.shortFocusMinutes(minutesUntil: next.minutesUntil),
              minutes < normalMinutes else { return nil }
        return ShortFocusOffer(eventTitle: next.title, minutesUntil: next.minutesUntil, focusMinutes: minutes)
    }

    /// 일정 5분 전에 끝나도록, 5분 단위로 내린 집중 분. 5분이 안 되면 nil.
    nonisolated static func shortFocusMinutes(minutesUntil: Int) -> Int? {
        guard minutesUntil < shortFocusThreshold else { return nil }
        let minutes = (minutesUntil - 5) / 5 * 5
        return minutes >= 5 ? minutes : nil
    }

    /// 할 일 끝냄 → Google 에서도 완료. 성공하면 목록에서 뺍니다.
    @discardableResult
    func complete(_ task: MuninnTask) async -> Bool {
        guard let client else { return false }
        let started = generation
        do {
            try await client.completeTask(list: task.list, id: task.id)
            guard started == generation else { return true }
            if let today {
                self.today = MuninnToday(date: today.date, tasks: today.tasks.filter { $0.key != task.key },
                                         nextEvent: today.nextEvent, google: today.google)
            }
            actionFailed = false
            return true
        } catch {
            if started == generation { actionFailed = true }
            return false
        }
    }

    // MARK: 하루 기록

    /// 마친 집중 한 줄을 대기열에 넣고 보내 봅니다. 닿지 않으면 남겨 두고 다음에 다시 보냅니다.
    func recordFocus(_ entry: JournalEntry, day: String) async {
        enqueue(entry, day: day)
        await flushJournal()
    }

    /// 곧바로(기다리지 않고) 저장되는 대기열에 넣습니다. 앱이 꺼지는 중이어도 남습니다.
    func enqueue(_ entry: JournalEntry, day: String) {
        guard isConfigured else { return }
        queue.append(PendingEntry(day: day, entry: entry))
        if queue.count > Self.queueLimit { queue.removeFirst(queue.count - Self.queueLimit) }
    }

    /// 대기열을 앞에서부터 보냅니다. 연결이 안 되면 멈추고, 서버가 내용을 받지 않는 줄(400·422)만 버립니다.
    /// 다른 400대(경로가 틀림, 프록시 등)는 남겨 두고 멈춥니다.
    func flushJournal() async {
        guard let client, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        while let first = queue.first {
            do {
                try await client.addJournalEntry(first.entry, day: first.day)
                queue.removeAll { $0.id == first.id }
            } catch MuninnError.http(let code) where code == 400 || code == 422 {
                queue.removeAll { $0.id == first.id }
            } catch {
                return
            }
        }
    }
}

/// 테스트 호스트용: 토큰이 없습니다.
private final class EmptyTokenStore: MuninnTokenStoring {
    func read() -> String? { nil }
    func save(_ token: String) throws {}
    func delete() {}
}
