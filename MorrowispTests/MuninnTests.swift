//
//  MuninnTests.swift
//  MorrowispTests
//
//  Muninn 연결: 오늘 할 일·다음 일정 읽기, 할 일 끝냄, 집중 뒤 하루 기록(기분), 오프라인 대기열.
//  실제 서버는 부르지 않습니다. URLProtocol 가짜로 요청을 받아 확인합니다.
//

import Foundation
import SwiftData
import Testing
@testable import Morrowisp

/// 요청을 적어 두고 정해 둔 응답을 돌려주는 가짜 URLProtocol. 테스트마다 다른 이름표(host)로 나눕니다.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Captured { let method: String; let url: URL; let headers: [String: String]; let body: Data? }
    typealias Responder = (URLRequest) -> (Int, Data)?   // nil → 연결 실패
    nonisolated(unsafe) static var responders: [String: Responder] = [:]
    nonisolated(unsafe) static var captured: [String: [Captured]] = [:]
    static let lock = NSLock()

    static func register(host: String, _ responder: @escaping Responder) {
        lock.withLock { responders[host] = responder; captured[host] = [] }
    }
    static func requests(host: String) -> [Captured] { lock.withLock { captured[host] ?? [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            stream.close(); body = data
        }
        let responder: Responder? = Self.lock.withLock {
            Self.captured[host, default: []].append(Captured(method: request.httpMethod ?? "GET", url: request.url!,
                                                             headers: request.allHTTPHeaderFields ?? [:], body: body))
            return Self.responders[host]
        }
        guard let (status, data) = responder?(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return
        }
        if (300..<400).contains(status) {
            // 다른 곳(같은 가짜 host 의 /elsewhere)으로 넘기는 응답
            let target = URL(string: "https://\(host)/elsewhere")!
            let redirect = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: redirect)
            // 따라가지 않기로 하면, 실제 서버처럼 302 응답 자체로 끝납니다.
            client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class MemoryTokenStore: MuninnTokenStoring {
    var token: String?
    init(_ token: String? = nil) { self.token = token }
    func read() -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() { token = nil }
}

private let token = "mnn_" + String(repeating: "a", count: 43)

private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

private let todayBody: [String: Any] = [
    "date": "2026-11-01", "timezone": "Asia/Seoul",
    "tasks": [
        ["list": "L1", "id": "t1", "title": "세미나 덱 결과 2장", "due": "2026-11-01", "overdue": false],
        ["list": "L1", "id": "t2", "title": "ADNI 용량 비우기", "due": "2026-10-30", "overdue": true],
        ["list": "L2", "id": "t3", "title": "메일 답장", "overdue": false]
    ],
    "events": [["title": "랩 세미나", "start": "2026-11-01T14:00:00+09:00", "end": "2026-11-01T15:00:00+09:00"]],
    "next_event": ["title": "랩 세미나", "start": "2026-11-01T14:00:00+09:00", "end": "2026-11-01T15:00:00+09:00"],
    "journal": ["entries": []]
]

/// 2026-11-01 12:40 KST
private let noon40 = ISO8601DateFormatter().date(from: "2026-11-01T12:40:00+09:00")!

@MainActor
struct MuninnClientTests {

    @Test func 주소는_http_https만_받고_끝의_빗금을_뗀다() {
        #expect(MuninnClient.validatedBaseURL(" https://g9.example.ts.net/ ")?.absoluteString == "https://g9.example.ts.net")
        #expect(MuninnClient.validatedBaseURL("http://127.0.0.1:8080")?.absoluteString == "http://127.0.0.1:8080")
        #expect(MuninnClient.validatedBaseURL("ftp://x") == nil)
        #expect(MuninnClient.validatedBaseURL("g9") == nil)
        #expect(MuninnClient.validatedBaseURL("") == nil)
    }

    @Test func whoami는_Bearer_토큰으로_묻고_이름을_돌려준다() async throws {
        StubURLProtocol.register(host: "whoami.test") { _ in (200, json(["auth": "token", "name": "morrowisp"])) }
        let client = MuninnClient(baseURL: URL(string: "https://whoami.test")!, token: token, session: StubURLProtocol.session())
        #expect(try await client.whoami() == "morrowisp")
        let request = try #require(StubURLProtocol.requests(host: "whoami.test").first)
        #expect(request.method == "GET")
        #expect(request.url.path() == "/api/whoami")
        #expect(request.headers["Authorization"] == "Bearer \(token)")
    }

    @Test func 다른_곳으로_넘기는_응답은_따라가지_않는다() async {
        StubURLProtocol.register(host: "redirect.test") { request in
            request.url!.path() == "/api/whoami" ? (302, Data()) : (200, json(["name": "elsewhere"]))
        }
        let client = MuninnClient(baseURL: URL(string: "https://redirect.test")!, token: token, session: StubURLProtocol.session())
        await #expect(throws: MuninnError.http(302), "넘긴 곳의 답을 받지 않는다") { try await client.whoami() }
        #expect(StubURLProtocol.requests(host: "redirect.test").map { $0.url.path() } == ["/api/whoami"], "토큰을 다른 곳으로 보내지 않는다")
    }

    @Test func 토큰이_틀리면_unauthorized() async {
        StubURLProtocol.register(host: "bad.test") { _ in (401, json(["error": "Invalid API token"])) }
        let client = MuninnClient(baseURL: URL(string: "https://bad.test")!, token: token, session: StubURLProtocol.session())
        await #expect(throws: MuninnError.unauthorized) { try await client.whoami() }
    }

    @Test func 오늘_응답을_읽는다() async throws {
        StubURLProtocol.register(host: "today.test") { _ in (200, json(todayBody)) }
        let client = MuninnClient(baseURL: URL(string: "https://today.test")!, token: token, session: StubURLProtocol.session())
        let today = try await client.today()
        #expect(today.date == "2026-11-01")
        #expect(today.tasks.map(\.id) == ["t1", "t2", "t3"])
        #expect(today.tasks[1].overdue)
        #expect(today.nextEvent?.title == "랩 세미나")
        #expect(today.nextEvent?.startDate == ISO8601DateFormatter().date(from: "2026-11-01T05:00:00Z"))
        #expect(today.google == nil)
        #expect(StubURLProtocol.requests(host: "today.test").first?.url.path() == "/api/today")
    }

    @Test func 일정의_summary_이름과_구글_끊김을_읽는다() async throws {
        StubURLProtocol.register(host: "gone.test") { _ in
            (200, json(["date": "2026-11-01", "google": "disconnected", "tasks": [],
                        "next_event": ["summary": "회의", "start": "2026-11-01T05:00:00.000Z"]]))
        }
        let client = MuninnClient(baseURL: URL(string: "https://gone.test")!, token: token, session: StubURLProtocol.session())
        let today = try await client.today()
        #expect(today.google == "disconnected")
        #expect(today.nextEvent?.title == "회의")
        #expect(today.nextEvent?.startDate != nil)
    }

    @Test func 할_일_끝냄은_경로를_인코딩하고_completed를_보낸다() async throws {
        StubURLProtocol.register(host: "done.test") { _ in (200, json(["status": "completed"])) }
        let client = MuninnClient(baseURL: URL(string: "https://done.test")!, token: token, session: StubURLProtocol.session())
        try await client.completeTask(list: "MDA/b c", id: "x?y#z")
        let request = try #require(StubURLProtocol.requests(host: "done.test").first)
        #expect(request.method == "PATCH")
        #expect(request.url.absoluteString == "https://done.test/api/tasks/MDA%2Fb%20c/x%3Fy%23z")
        let body = try #require(request.body)
        #expect(try JSONSerialization.jsonObject(with: body) as? [String: String] == ["status": "completed"])
    }

    @Test func 하루_기록은_날짜_경로로_보내고_기분이_없으면_빼고_보낸다() async throws {
        StubURLProtocol.register(host: "journal.test") { _ in (201, json([:])) }
        let client = MuninnClient(baseURL: URL(string: "https://journal.test")!, token: token, session: StubURLProtocol.session())
        try await client.addJournalEntry(JournalEntry(minutes: 25, mood: 4, text: "덱", time: "13:55"), day: "2026-11-01")
        try await client.addJournalEntry(JournalEntry(minutes: 15, mood: nil, text: ""), day: "2026-11-01")
        let requests = StubURLProtocol.requests(host: "journal.test")
        #expect(requests.map(\.method) == ["POST", "POST"])
        #expect(requests[0].url.path() == "/api/journal/2026-11-01/entries")
        let first = try JSONSerialization.jsonObject(with: requests[0].body!) as? [String: AnyHashable]
        #expect(first == ["kind": "focus", "minutes": 25, "mood": 4, "text": "덱", "time": "13:55"])
        let second = try JSONSerialization.jsonObject(with: requests[1].body!) as? [String: AnyHashable]
        #expect(second == ["kind": "focus", "minutes": 15, "text": ""])
    }
}

@MainActor
struct MuninnServiceTests {
    private let clock = TestClock()
    private let tokens = MemoryTokenStore(token)

    private func service(host: String, defaults: UserDefaults? = nil, tokens: MemoryTokenStore? = nil) -> MuninnService {
        let clock = self.clock
        let service = MuninnService(defaults: defaults, tokens: tokens ?? self.tokens, session: StubURLProtocol.session(), now: { clock.date })
        service.baseURLString = "https://\(host)"
        return service
    }

    @Test func 주소나_토큰이_없으면_연결되지_않은_것으로_본다() {
        let service = MuninnService(defaults: nil, tokens: MemoryTokenStore(), session: StubURLProtocol.session())
        #expect(!service.isConfigured)
        service.baseURLString = "https://x.test"
        #expect(!service.isConfigured, "토큰 없음")
        try? service.saveToken("  \(token)\n")
        #expect(service.isConfigured)
        #expect(service.hasToken)
        service.removeToken()
        #expect(!service.isConfigured)
    }

    @Test func 토큰은_UserDefaults에_남지_않는다() throws {
        let suite = "MuninnTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryTokenStore()
        let service = MuninnService(defaults: defaults, tokens: store, session: StubURLProtocol.session())
        service.baseURLString = "https://x.test"
        try service.saveToken(token)
        #expect(store.token == token)
        let persisted = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(persisted["muninnBaseURL"] as? String == "https://x.test")
        for value in persisted.values {
            #expect(!"\(value)".contains("mnn_"), "토큰이 설정 파일에 들어가면 안 된다")
        }
    }

    @Test func 지난_기한을_먼저_보이고_60초_안에는_다시_부르지_않는다() async {
        StubURLProtocol.register(host: "svc-today.test") { _ in (200, json(todayBody)) }
        let service = service(host: "svc-today.test")
        await service.refresh()
        #expect(service.status == .loaded)
        #expect(service.sortedTasks.map(\.id) == ["t2", "t1", "t3"])
        await service.refresh()
        clock.advance(59)
        await service.refresh()
        #expect(StubURLProtocol.requests(host: "svc-today.test").count == 1)
        clock.advance(2)
        await service.refresh()
        #expect(StubURLProtocol.requests(host: "svc-today.test").count == 2)
    }

    @Test func 연결이_안_되거나_구글이_끊기면_조용한_상태만_바꾼다() async {
        StubURLProtocol.register(host: "svc-down.test") { _ in nil }
        let down = service(host: "svc-down.test")
        await down.refresh()
        #expect(down.status == .unreachable)
        #expect(down.sortedTasks.isEmpty)

        StubURLProtocol.register(host: "svc-gone.test") { _ in (200, json(["date": "2026-11-01", "google": "disconnected"])) }
        let gone = service(host: "svc-gone.test")
        await gone.refresh()
        #expect(gone.status == .googleDisconnected)

        StubURLProtocol.register(host: "svc-401.test") { _ in (401, json([:])) }
        let denied = service(host: "svc-401.test")
        await denied.refresh()
        #expect(denied.status == .unauthorized)
    }

    @Test func 다음_일정과_짧은_집중_제안() async {
        StubURLProtocol.register(host: "svc-event.test") { _ in (200, json(todayBody)) }
        let service = service(host: "svc-event.test")
        clock.date = noon40
        await service.refresh()
        #expect(service.nextEvent?.minutesUntil == 80)
        #expect(service.shortFocusOffer(normalMinutes: 25) == nil, "80분 남았으면 제안하지 않는다")

        clock.date = noon40.addingTimeInterval(60 * 60) // 13:40, 20분 남음
        #expect(service.nextEvent?.minutesUntil == 20)
        #expect(service.shortFocusOffer(normalMinutes: 25)?.focusMinutes == 15, "일정 전에 끝나는 15분")
        #expect(service.shortFocusOffer(normalMinutes: 10) == nil, "평소 집중이 이미 일정 전에 끝나면 따로 묻지 않는다")
        clock.date = noon40.addingTimeInterval(76 * 60) // 13:56, 4분 남음
        #expect(service.shortFocusOffer(normalMinutes: 25) == nil, "너무 짧으면 제안하지 않는다")
        clock.date = noon40.addingTimeInterval(81 * 60) // 지남
        #expect(service.nextEvent == nil)
    }

    @Test func 짧은_집중_분은_일정_5분_전에_끝나도록_5분_단위로_내린다() {
        #expect(MuninnService.shortFocusMinutes(minutesUntil: 24) == 15)
        #expect(MuninnService.shortFocusMinutes(minutesUntil: 20) == 15)
        #expect(MuninnService.shortFocusMinutes(minutesUntil: 12) == 5)
        #expect(MuninnService.shortFocusMinutes(minutesUntil: 9) == nil)
        #expect(MuninnService.shortFocusMinutes(minutesUntil: 25) == nil)
    }

    @Test func 끝냄에_성공하면_목록에서_빠지고_실패하면_남는다() async {
        StubURLProtocol.register(host: "svc-done.test") { request in
            request.httpMethod == "PATCH" ? (request.url!.path().contains("t2") ? (200, json([:])) : (500, json([:]))) : (200, json(todayBody))
        }
        let service = service(host: "svc-done.test")
        await service.refresh()
        let tasks = service.sortedTasks
        #expect(await service.complete(tasks[0]))
        #expect(service.sortedTasks.map(\.id) == ["t1", "t3"])
        #expect(!(await service.complete(service.sortedTasks[0])))
        #expect(service.sortedTasks.map(\.id) == ["t1", "t3"])
        #expect(service.actionFailed)
    }

    @Test func 하루_기록은_오프라인이면_쌓였다가_다시_보낸다() async throws {
        let suite = "MuninnQueue-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        nonisolated(unsafe) var online = false
        StubURLProtocol.register(host: "svc-queue.test") { _ in online ? (201, json([:])) : nil }
        let service = service(host: "svc-queue.test", defaults: defaults)
        await service.recordFocus(JournalEntry(minutes: 25, mood: 4, text: "a"), day: "2026-11-01")
        await service.recordFocus(JournalEntry(minutes: 15, mood: nil, text: "b"), day: "2026-11-01")
        #expect(service.pendingJournalCount == 2)

        // 앱을 다시 켜도 남아 있다
        let reopened = self.service(host: "svc-queue.test", defaults: defaults)
        #expect(reopened.pendingJournalCount == 2)

        online = true
        await reopened.flushJournal()
        #expect(reopened.pendingJournalCount == 0)
        let posted = StubURLProtocol.requests(host: "svc-queue.test").filter { $0.method == "POST" }.suffix(2)
        let texts = posted.compactMap { try? JSONSerialization.jsonObject(with: $0.body!) as? [String: AnyHashable] }.map { $0["text"] }
        #expect(texts == ["a", "b"], "순서대로 보낸다")
    }

    @Test func 경로가_틀린_404에는_대기열을_버리지_않고_400에는_그_줄만_버린다() async {
        nonisolated(unsafe) var code = 404
        StubURLProtocol.register(host: "svc-4xx.test") { _ in (code, json([:])) }
        let service = service(host: "svc-4xx.test")
        await service.recordFocus(JournalEntry(minutes: 25, mood: nil, text: "a"), day: "2026-11-01")
        #expect(service.pendingJournalCount == 1)
        code = 400
        await service.flushJournal()
        #expect(service.pendingJournalCount == 0)
    }

    @Test func 주소를_바꾸면_그_전에_떠난_답은_버린다() async throws {
        StubURLProtocol.register(host: "svc-slow.test") { _ in Thread.sleep(forTimeInterval: 0.4); return (200, json(todayBody)) }
        let service = service(host: "svc-slow.test")
        let pending = Task { await service.refresh() }
        try await Task.sleep(for: .milliseconds(100))
        service.baseURLString = "https://svc-other.test"
        await pending.value
        #expect(service.today == nil)
        #expect(service.status == .notLoaded)
    }

    @Test func 늦게_보낸_기록도_끝난_시각과_날짜를_그대로_보낸다() async throws {
        nonisolated(unsafe) var online = false
        StubURLProtocol.register(host: "svc-late.test") { _ in online ? (201, json([:])) : nil }
        let service = service(host: "svc-late.test")
        // 23:58 에 끝난 집중을 오프라인으로 쌓아 두고, 자정이 지난 뒤 보냅니다.
        await service.recordFocus(JournalEntry(minutes: 25, mood: 3, text: "a", time: "23:58"), day: "2026-10-31")
        clock.advance(3600)
        online = true
        await service.flushJournal()
        let request = try #require(StubURLProtocol.requests(host: "svc-late.test").last)
        #expect(request.url.path() == "/api/journal/2026-10-31/entries")
        let body = try JSONSerialization.jsonObject(with: request.body!) as? [String: AnyHashable]
        #expect(body?["time"] as? String == "23:58")
    }

    @Test func 시각은_사용자_시간대의_24시간_HH_mm() {
        var seoul = Calendar(identifier: .gregorian)
        seoul.timeZone = TimeZone(identifier: "Asia/Seoul")!
        #expect(JournalEntry.timeString(for: noon40, calendar: seoul) == "12:40")
        #expect(JournalEntry.timeString(for: noon40.addingTimeInterval(11 * 3600 + 18 * 60), calendar: seoul) == "23:58")
        var utc = seoul; utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(JournalEntry.timeString(for: noon40, calendar: utc) == "03:40")
    }

    @Test func 연결하지_않았으면_하루_기록을_쌓지_않는다() async {
        let service = MuninnService(defaults: nil, tokens: MemoryTokenStore(), session: StubURLProtocol.session())
        await service.recordFocus(JournalEntry(minutes: 25, mood: 3, text: "a"), day: "2026-11-01")
        #expect(service.pendingJournalCount == 0)
    }
}

@MainActor
struct FocusJournalHookTests {
    private let clock = TestClock()
    private let settings: AppSettings
    private let container: ModelContainer
    private let appDelegate = AppDelegate()
    private let recorder = ShortcutRecorder()
    private let journal = JournalRecorder()
    private let viewModel: PomodoroViewModel

    @MainActor final class JournalRecorder {
        var entries: [(JournalEntry, String)] = []
    }

    init() throws {
        let settings = AppSettings(defaults: nil)
        settings.notificationSoundName = AppSettings.soundOff
        settings.focusStartShortcut = "시작"
        self.settings = settings
        container = try ModelContainer(for: FocusLogEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let clock = self.clock
        let journal = self.journal
        viewModel = PomodoroViewModel(
            modelContext: container.mainContext, appDelegate: appDelegate, settings: settings,
            shortcuts: recorder,
            recordFocusJournal: { journal.entries.append(($0, $1)) },
            now: { clock.date }
        )
    }

    private func runOutTheClock() {
        clock.advance(viewModel.timeRemaining)
        viewModel.tick()
    }

    @Test func 짧은_집중은_이번_한_번만_정한_분으로_시작한다() {
        viewModel.startFocusSession(minutes: 15)
        #expect(viewModel.currentState == .focus)
        #expect(viewModel.timeRemaining == 15 * 60)
        #expect(recorder.names == ["시작"], "시작 단축어는 그대로 한 번")
        viewModel.startFocusSession(minutes: 5)
        #expect(viewModel.timeRemaining == 15 * 60, "도는 중에는 다시 시작하지 않는다")
        #expect(settings.focusDurationInMinutes == 25, "설정은 바뀌지 않는다")
    }

    @Test func 집중을_마치면_기분과_함께_하루_기록을_남긴다() {
        clock.date = noon40
        viewModel.focusTask = "  덱 2장 "
        viewModel.startFocusSession(minutes: 15)
        runOutTheClock()
        #expect(viewModel.timerState == .awaitingChoice)
        viewModel.setMood(4)
        #expect(viewModel.focusMood == 4)
        viewModel.setMood(4)
        #expect(viewModel.focusMood == nil, "같은 얼굴을 다시 누르면 지운다")
        viewModel.setMood(5)
        #expect(journal.entries.isEmpty, "고르기 전에는 보내지 않는다")
        viewModel.startBreakAfterFocus()
        #expect(journal.entries.count == 1)
        let (entry, day) = journal.entries[0]
        // 12:40 에 시작한 15분 집중 → 12:55 (KST). 테스트 기기의 시간대와 상관없이 같은 달력으로 확인합니다.
        let end = noon40.addingTimeInterval(15 * 60)
        #expect(entry == JournalEntry(minutes: 15, mood: 5, text: "덱 2장", time: JournalEntry.timeString(for: end)))
        #expect(day == DailyMissionStore.dayKey(for: end))
        #expect(viewModel.focusMood == nil, "다음 집중으로 넘어가지 않는다")
    }

    @Test func 기분은_건너뛸_수_있고_연장한_집중은_한_번만_기록한다() {
        let start = clock.date
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.extendFocus()
        runOutTheClock()
        viewModel.startBreakAfterFocus()
        #expect(journal.entries.map(\.0) == [JournalEntry(minutes: 35, mood: nil, text: "",
                                                          time: JournalEntry.timeString(for: start.addingTimeInterval(35 * 60)))])
    }

    @Test func 기분은_선택_화면에서만_1에서_5까지_고른다() {
        viewModel.setMood(3)
        #expect(viewModel.focusMood == nil)
        viewModel.startFocusSession()
        viewModel.setMood(3)
        #expect(viewModel.focusMood == nil)
        runOutTheClock()
        viewModel.setMood(9)
        #expect(viewModel.focusMood == nil, "범위 밖")
        viewModel.setMood(0)
        #expect(viewModel.focusMood == nil)
        viewModel.setMood(1)
        #expect(viewModel.focusMood == 1)
    }

    @Test func 선택_화면에서_초기화하거나_앱을_꺼도_한_번만_기록한다() {
        let start = clock.date
        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.setMood(2)
        clock.advance(600) // 선택 화면에서 오래 있다가 눌러도, 시각은 시간이 다 된 때
        viewModel.resetToIdle()
        #expect(journal.entries.map(\.0) == [JournalEntry(minutes: 25, mood: 2, text: "",
                                                          time: JournalEntry.timeString(for: start.addingTimeInterval(25 * 60)))])

        viewModel.startFocusSession()
        runOutTheClock()
        viewModel.logInterruptedSession()
        viewModel.logInterruptedSession()
        #expect(journal.entries.count == 2)
    }

    @Test func 전환_관리를_끄면_기분_없이_마친_집중만_기록한다() {
        settings.transitionManagementEnabled = false
        let start = clock.date
        viewModel.startFocusSession()
        runOutTheClock()
        #expect(viewModel.currentState == .shortBreak)
        #expect(journal.entries.map(\.0) == [JournalEntry(minutes: 25, mood: nil, text: "",
                                                          time: JournalEntry.timeString(for: start.addingTimeInterval(25 * 60)))])
    }

    @Test func 건너뛰거나_초기화한_집중은_기록하지_않는다() {
        viewModel.startFocusSession()
        clock.advance(120)
        viewModel.skipToNextSession()
        clock.advance(30)
        viewModel.resetToIdle()
        viewModel.startFocusSession()
        clock.advance(120)
        viewModel.resetToIdle()
        #expect(journal.entries.isEmpty)
    }
}

struct SettingsSectionTests {
    @Test func 마지막에_연_설정_칸을_기억하고_모르는_값이면_타이머로() {
        #expect(SettingsSection(stored: "muninn") == .muninn)
        #expect(SettingsSection(stored: "general") == .general)
        #expect(SettingsSection(stored: "nope") == .timer)
        #expect(SettingsSection.allCases.count == 6)
    }
}
