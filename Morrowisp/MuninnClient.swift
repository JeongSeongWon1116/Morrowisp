// File: MuninnClient.swift
// Description: Muninn 서버(개인 API 토큰)와 주고받는 작은 HTTP 클라이언트와 응답 모양.
// 토큰은 키체인에만 둡니다. 로그·UserDefaults 에는 남기지 않습니다.

import Foundation
import Security

// MARK: - 응답 모양

struct MuninnTask: Codable, Equatable {
    let list: String
    let id: String
    let title: String
    let due: String?
    let overdue: Bool

    /// 목록이 달라도 id 가 겹칠 수 있어, 화면에서는 목록과 함께 구분합니다.
    var key: String { list + "\u{1F}" + id }

    init(list: String, id: String, title: String, due: String? = nil, overdue: Bool = false) {
        self.list = list; self.id = id; self.title = title; self.due = due; self.overdue = overdue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        list = try c.decode(String.self, forKey: .list)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        due = try? c.decodeIfPresent(String.self, forKey: .due)
        overdue = (try? c.decodeIfPresent(Bool.self, forKey: .overdue)) ?? false
    }
}

struct MuninnEvent: Equatable, Decodable {
    let title: String
    let start: String?

    private enum CodingKeys: String, CodingKey { case title, summary, start }

    init(title: String, start: String?) { self.title = title; self.start = start }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title))
            ?? (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        start = try? c.decodeIfPresent(String.self, forKey: .start)
    }

    /// 하루 종일 일정(날짜만)은 시각이 없으므로 nil 입니다.
    var startDate: Date? {
        guard let start else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: start) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: start)
    }
}

struct MuninnToday: Equatable, Decodable {
    let date: String
    let tasks: [MuninnTask]
    let nextEvent: MuninnEvent?
    /// "disconnected" 이면 Muninn 은 닿지만 Google 이 연결되어 있지 않습니다.
    let google: String?

    private enum CodingKeys: String, CodingKey { case date, tasks, nextEvent = "next_event", google }

    init(date: String, tasks: [MuninnTask], nextEvent: MuninnEvent? = nil, google: String? = nil) {
        self.date = date; self.tasks = tasks; self.nextEvent = nextEvent; self.google = google
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? ""
        tasks = (try? c.decodeIfPresent([MuninnTask].self, forKey: .tasks)) ?? []
        nextEvent = try? c.decodeIfPresent(MuninnEvent.self, forKey: .nextEvent)
        google = try? c.decodeIfPresent(String.self, forKey: .google)
    }
}

/// 하루 기록 한 줄: 집중을 마친 분, 고른 기분(1~5, 고르지 않으면 없음), 할 일.
struct JournalEntry: Codable, Equatable {
    var kind = "focus"
    let minutes: Int
    let mood: Int?
    let text: String

    init(minutes: Int, mood: Int?, text: String) {
        self.minutes = minutes; self.mood = mood; self.text = text
    }
}

enum MuninnError: Error, Equatable {
    case unauthorized
    case http(Int)
    case unreachable
    case invalidResponse
    case keychain(Int32)
}

// MARK: - 클라이언트

struct MuninnClient {
    let baseURL: URL
    let token: String
    let session: URLSession

    /// 사용자가 적은 주소를 http(s)://host[:port][/path] 로 받아 끝의 빗금을 뗍니다. 아니면 nil.
    static func validatedBaseURL(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty,
              url.query == nil, url.fragment == nil, url.user == nil else { return nil }
        return url
    }

    /// 경로 한 조각. 빗금·물음표·# 도 그대로 두지 않습니다.
    static func encodePathPart(_ part: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;%")
        return part.addingPercentEncoding(withAllowedCharacters: allowed) ?? part
    }

    func whoami() async throws -> String {
        let data = try await send("GET", "/api/whoami")
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["name"] as? String ?? ""
    }

    func today() async throws -> MuninnToday {
        let data = try await send("GET", "/api/today")
        do { return try JSONDecoder().decode(MuninnToday.self, from: data) } catch { throw MuninnError.invalidResponse }
    }

    func completeTask(list: String, id: String) async throws {
        let path = "/api/tasks/\(Self.encodePathPart(list))/\(Self.encodePathPart(id))"
        _ = try await send("PATCH", path, body: try JSONEncoder().encode(["status": "completed"]))
    }

    func addJournalEntry(_ entry: JournalEntry, day: String) async throws {
        _ = try await send("POST", "/api/journal/\(Self.encodePathPart(day))/entries", body: try JSONEncoder().encode(entry))
    }

    private func send(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw MuninnError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: NoRedirects.shared)
        } catch {
            throw MuninnError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw MuninnError.invalidResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw MuninnError.unauthorized
        default: throw MuninnError.http(http.statusCode)
        }
    }
}

/// 다른 곳으로 넘기는 응답을 따라가지 않습니다. 토큰이 다른 주소로 가지 않게 합니다.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirects()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// MARK: - 토큰 보관

protocol MuninnTokenStoring: AnyObject {
    func read() -> String?
    func save(_ token: String) throws
    func delete()
}

/// macOS 키체인(일반 암호). 이 앱만 읽습니다.
final class KeychainTokenStore: MuninnTokenStoring {
    private let service = "dev.swsquare.morrowisp.muninn"
    private let account = "api-token"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw MuninnError.keychain(added) }
        } else if status != errSecSuccess {
            throw MuninnError.keychain(status)
        }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
