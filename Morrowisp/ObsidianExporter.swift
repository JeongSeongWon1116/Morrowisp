// File: ObsidianExporter.swift
// Description: 완료된 세션을 Obsidian 보관함(Vault)의 데일리 노트(yyyy-MM-dd.md)에
// 마크다운으로 기록하는 연동 모듈입니다. 별도의 Obsidian 플러그인 없이 동작합니다.

import Foundation
import AppKit

@MainActor
final class ObsidianExporter: ObservableObject {
    static let shared: ObsidianExporter = {
        #if DEBUG
        if PreviewHarness.isActive { return ObsidianExporter(defaults: nil) }
        #endif
        return ObsidianExporter()
    }()

    private static let enabledKey = "obsidianSyncEnabled"
    private static let bookmarkKey = "obsidianFolderBookmark"
    static let sectionHeading = "## 🍅 뽀모도로"
    static let statsPrefix = "**하루 통계:**"
    static let missionPrefix = "\t- 오늘의 메인 미션: "

    @Published var isEnabled: Bool {
        didSet {
            defaults?.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { syncTodayMission() }
        }
    }
    @Published private(set) var folderName: String?

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults?.bool(forKey: Self.enabledKey) ?? false
        self.folderName = nil
        if let url = resolveFolderURL() {
            self.folderName = url.lastPathComponent
        }
    }

    var isFolderSelected: Bool {
        defaults?.data(forKey: Self.bookmarkKey) != nil
    }

    /// 데일리 노트가 저장되는 보관함 폴더를 선택합니다.
    /// 샌드박스 환경에서 재실행 후에도 접근할 수 있도록 보안 범위 북마크로 저장합니다.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose the Obsidian folder that holds your daily notes")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveBookmark(for: url)
        syncTodayMission()
    }

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults?.set(data, forKey: Self.bookmarkKey)
            folderName = url.lastPathComponent
        } catch {
            print("Obsidian 폴더 북마크 저장 실패: \(error)")
        }
    }

    private func resolveFolderURL() -> URL? {
        guard let data = defaults?.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale {
            saveBookmark(for: url)
        }
        return url
    }

    /// 완료된 세션을 해당 날짜의 데일리 노트에 추가합니다.
    /// 노트가 없으면 새로 만들고, "## 🍅 뽀모도로" 섹션이 있으면 그 끝에 줄을 추가합니다.
    /// details 가 있으면 할 일·보상·다음 시작점·연장을 기록 줄 아래에 들여쓴 줄로 붙입니다.
    func appendSession(_ entry: FocusLogEntry, details: TransitionDetails? = nil) {
        // 단위 테스트가 실제 보관함에 쓰지 않도록 합니다. (파일 처리는 appendLine 으로 따로 검증)
        if DataController.isRunningTests { return }
        guard isEnabled, let folder = resolveFolderURL() else { return }
        guard folder.startAccessingSecurityScopedResource() else {
            print("Obsidian 폴더 접근 권한을 얻지 못했습니다.")
            return
        }
        defer { folder.stopAccessingSecurityScopedResource() }

        let noteURL = folder.appendingPathComponent(Self.noteFileName(for: entry.startTime))
        do {
            let settings = AppSettings.shared
            let mission = settings.transitionManagementEnabled ? settings.dailyMissions.mission(for: entry.startTime) : nil
            try Self.appendSession(entry, details: details, toNoteAt: noteURL, mission: mission)
        } catch {
            print("Obsidian 데일리 노트 기록 실패: \(error)")
        }
    }

    /// 파일 처리를 분리해 검증하며, 빈 로컬 미션으로 노트에 있던 미션을 지우지 않습니다.
    static func appendSession(_ entry: FocusLogEntry, details: TransitionDetails? = nil,
                              toNoteAt noteURL: URL, mission: DailyMission? = nil) throws {
        let sessionMission: DailyMission? = mission.flatMap { singleLine($0.text).isEmpty ? nil : $0 }
        try appendLine(markdownLines(for: entry, details: details), toNoteAt: noteURL, mission: sessionMission)
    }

    private func syncTodayMission() {
        let today = Date()
        updateMission(AppSettings.shared.dailyMissions.mission(for: today), for: today)
    }

    /// 미션만 적거나 고친 날에도 남깁니다. 기존 섹션과 파일 읽기 보호를 그대로 사용합니다.
    func updateMission(_ mission: DailyMission, for date: Date) {
        if DataController.isRunningTests { return }
        guard isEnabled, AppSettings.shared.transitionManagementEnabled,
              let folder = resolveFolderURL(), folder.startAccessingSecurityScopedResource() else { return }
        defer { folder.stopAccessingSecurityScopedResource() }
        let noteURL = folder.appendingPathComponent(Self.noteFileName(for: date))
        // 빈 미션을 지우는 동작으로 새 빈 노트를 만들지는 않습니다.
        guard !mission.text.isEmpty || FileManager.default.fileExists(atPath: noteURL.path) else { return }
        do {
            try Self.appendLine(nil, toNoteAt: noteURL, mission: mission)
        } catch {
            print("Obsidian 메인 미션을 기록하지 못했습니다: \(error)")
        }
    }

    enum NoteError: Error {
        /// 노트가 이미 있는데 UTF-8 텍스트로 읽을 수 없음 (다른 인코딩, 권한, 내려받기 실패 등)
        case unreadableExistingNote(URL, underlying: Error)
        /// iCloud 에서 아직 내려받지 않은 노트 (".이름.icloud" 자리표시자만 있음)
        case notDownloadedFromICloud(URL)
    }

    /// 데일리 노트 파일을 읽어 기록 줄을 넣고 다시 씁니다.
    /// 변경이 있을 때만 쓰며, 노트가 없으면 새로 만듭니다. 읽지 못하는 기존 노트는 덮어쓰지 않고
    /// 오류를 던집니다. (기록은 앱 안에 남아 있으므로 잃는 것이 없습니다.)
    static func appendLine(_ line: String?, toNoteAt noteURL: URL, mission: DailyMission? = nil) throws {
        let existing: String
        if FileManager.default.fileExists(atPath: noteURL.path) {
            do {
                existing = try String(contentsOf: noteURL, encoding: .utf8)
            } catch {
                throw NoteError.unreadableExistingNote(noteURL, underlying: error)
            }
        } else {
            let placeholder = noteURL.deletingLastPathComponent()
                .appendingPathComponent("." + noteURL.lastPathComponent + ".icloud")
            guard !FileManager.default.fileExists(atPath: placeholder.path) else {
                throw NoteError.notDownloadedFromICloud(noteURL)
            }
            existing = ""
        }
        let updated = insert(line: line, into: existing, mission: mission)
        guard updated != existing else { return }
        try updated.write(to: noteURL, atomically: true, encoding: .utf8)
    }

    static func noteFileName(for date: Date) -> String {
        DailyMissionStore.dayKey(for: date) + ".md"
    }

    static func markdownLine(for entry: FocusLogEntry) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let start = timeFormatter.string(from: entry.startTime)
        // 종료 시각 = 시작 + 활동 시간 + 정지 시간
        let end = timeFormatter.string(from: entry.startTime.addingTimeInterval(entry.duration + entry.pausedDuration))
        return "- \(entry.sessionType.emoji) \(entry.sessionType.rawValue) \(durationText(entry.duration)) (\(start)–\(end))"
    }

    /// 기록 줄과, 그 아래에 들여써 붙이는 할 일·보상·다음 시작점·연장 줄.
    /// 기록 줄 자체는 markdownLine 과 같아서 하루 통계 계산에 영향을 주지 않습니다.
    static func markdownLines(for entry: FocusLogEntry, details: TransitionDetails?) -> String {
        var lines = [markdownLine(for: entry)]
        guard let details else { return lines[0] }
        for (label, text) in [("할 일", details.task), ("보상", details.reward), ("다음 시작점", details.nextStartingPoint)] {
            let flattened = singleLine(text)
            if !flattened.isEmpty { lines.append("\t- \(label): \(flattened)") }
        }
        if details.extensionCount > 0 {
            let minutes = details.extensionCount * Int(PomodoroViewModel.focusExtension / 60)
            lines.append("\t- 연장: +\(minutes)분")
        }
        return lines.joined(separator: "\n")
    }

    /// 줄바꿈을 공백으로 펴고 앞뒤 공백을 뗍니다. (적은 글이 노트의 줄 구조를 깨지 않도록)
    /// "%%" 는 Obsidian 의 주석 표시라, 짝이 없으면 뒤의 내용이 화면에서 숨으므로 사이를 띄웁니다.
    private static func singleLine(_ text: String) -> String {
        var flattened = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        while flattened.contains("%%") {
            flattened = flattened.replacingOccurrences(of: "%%", with: "% %")
        }
        return flattened
    }

    /// 초 단위까지 표시하는 시간 문자열 (예: "1시간 2분 3초", "25분", "42초")
    static func durationText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)시간") }
        if minutes > 0 { parts.append("\(minutes)분") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds)초") }
        return parts.joined(separator: " ")
    }

    /// 섹션에 새 기록 줄을 추가하고, 하루 통계 줄을 다시 계산하여 하나로 유지합니다.
    static func insert(line: String?, into content: String, mission: DailyMission? = nil) -> String {
        let (prefix, body, suffix, hasSection) = splitSection(in: content)

        // 기존 통계 줄은 버리고(중복 방지) 나머지 줄은 그대로 보존합니다.
        var lines = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.hasPrefix(statsPrefix) }
        var missionLine = lines.first { $0.hasPrefix(missionPrefix) }
        lines.removeAll { $0.hasPrefix(missionPrefix) }
        if let mission {
            let text = singleLine(mission.text)
            missionLine = text.isEmpty ? nil : missionPrefix + (mission.done ? "✓ " : "") + text
        }
        if let line, !line.isEmpty { lines.append(line) }

        guard hasSection || missionLine != nil || !lines.isEmpty else { return content }
        let missionHeader = missionLine.map { $0 + "\n" } ?? ""
        let bodyLines = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        let section = sectionHeading + "\n" + missionHeader + statsLine(for: lines) + "\n" + bodyLines
        return prefix + section + suffix
    }

    /// 섹션 줄들로부터 하루 통계(집중 횟수 + 총 집중 시간)를 계산합니다.
    static func statsLine(for lines: [String]) -> String {
        let focusLines = lines.filter { $0.hasPrefix("- " + PomodoroState.focus.emoji) }
        let totalSeconds = focusLines.reduce(0) { $0 + parseDurationSeconds(fromLine: $1) }
        return "\(statsPrefix) \(PomodoroState.focus.emoji) \(focusLines.count)회 · 총 \(durationText(TimeInterval(totalSeconds)))"
    }

    /// "- 🍅 집중 24분 13초 (09:00–09:25)" 형태의 줄에서 시간을 초로 파싱합니다.
    static func parseDurationSeconds(fromLine line: String) -> Int {
        let beforeTimes = line.components(separatedBy: " (").first ?? line
        var seconds = 0
        for token in beforeTimes.split(separator: " ") {
            if token.hasSuffix("시간"), let value = Int(token.dropLast(2)) {
                seconds += value * 3600
            } else if token.hasSuffix("분"), let value = Int(token.dropLast()) {
                seconds += value * 60
            } else if token.hasSuffix("초"), let value = Int(token.dropLast()) {
                seconds += value
            }
        }
        return seconds
    }

    /// 노트를 (섹션 앞, 섹션 본문, 섹션 뒤, 섹션 존재 여부)로 분리합니다. 섹션이 없으면 본문은 빈 문자열입니다.
    /// 섹션 헤딩은 줄 전체가 일치해야 하고, 섹션은 다음 마크다운 헤딩("#" 여러 개 + 공백)에서 끝납니다.
    /// ("#태그" 줄은 헤딩이 아니므로 섹션 안에 그대로 둡니다.)
    private static func splitSection(in content: String) -> (prefix: String, body: String, suffix: String, hasSection: Bool) {
        let lines = content.components(separatedBy: "\n")
        guard let headingIndex = lines.firstIndex(where: { trimmedLineEnd($0) == sectionHeading }) else {
            var prefix = content
            if !prefix.isEmpty && !prefix.hasSuffix("\n") { prefix += "\n" }
            if !prefix.isEmpty { prefix += "\n" }
            return (prefix, "", "", false)
        }

        let endIndex = lines[(headingIndex + 1)...].firstIndex(where: isMarkdownHeading) ?? lines.count

        let prefix = lines[..<headingIndex].map { $0 + "\n" }.joined()
        let body = lines[(headingIndex + 1)..<endIndex].joined(separator: "\n")
        let suffix = endIndex < lines.count ? "\n" + lines[endIndex...].joined(separator: "\n") : ""
        return (prefix, body, suffix, true)
    }

    /// 줄 끝의 공백과 CR(윈도우 줄바꿈)을 뗀 문자열
    private static func trimmedLineEnd(_ line: String) -> String {
        var trimmed = Substring(line)
        while let last = trimmed.last, last == " " || last == "\t" || last == "\r" || last == "\r\n" {
            trimmed = trimmed.dropLast()
        }
        return String(trimmed)
    }

    /// 마크다운 헤딩 줄인지 판정합니다: "#" 1~6개 뒤에 공백.
    private static func isMarkdownHeading(_ line: String) -> Bool {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return false }
        return line.dropFirst(hashes.count).first == " "
    }
}
