# Changelog

Older entries are in Korean.

이 프로젝트는 [유의적 버전(Semantic Versioning)](https://semver.org/lang/ko/)을 따릅니다.

## [2.1.0] - 2026-11-01

### Added
- Start-focus prompt: with transition support on and the timer idle, the popover offers today's unfinished mission with a Start focus button. No notifications or auto start.
- Muninn connection (Settings > Muninn): server address and a personal API token stored in the Keychain. When connected, the popover shows today's Google tasks (overdue first) and the next event, offers a shorter focus that ends before an event under 25 minutes away, and marks tasks done in Google.
- Optional mood tap (five faces) when a focus ends; each finished focus is added to the Muninn daily journal with its end time, queued and retried when offline.

### Changed
- Popover in two columns (timer and controls on the left; prompt, tasks, notes and summary on the right), about a third as tall.
- Settings use a sidebar instead of top tabs and remember the last section.

## [2.0.1] - 2026-10-16

### Changed
- Wider Settings window (540×460) so every tab shows in English; shorter "Transition support" label and a two-sentence note.
- Reward list: no repeated "Reward name" labels, left-aligned fields, a small + per size.
- History window: no "Choose period" label, a wider session list, numbers only in the weekly table, a clearer weekly title.
- Popover: the day summary is hidden during the first focus session and leaves out extensions when there are none; the main mission field wraps to three lines.

### Added
- A getting-started guide with screenshots: [docs/GUIDE.md](docs/GUIDE.md) and [docs/GUIDE.ko.md](docs/GUIDE.ko.md).

## [2.0.0] - 2026-10-16

### Changed
- Launched **Morrowisp** by **SW Square** as a new app, version 2.0.0 (build 8), installed as `Morrowisp.app` with bundle identifier `dev.swsquare.morrowisp`.
- Renamed the Xcode project, app and test targets, modules, and release artifacts to Morrowisp, and added a shared Morrowisp scheme.
- Separated automatic updates with `morrowisp-appcast.xml` in the Morrowisp repository, retaining the existing EdDSA public key.
- Added the copyright notice **© 2026 SW Square** to app metadata and Settings > General > About.
- Added English and Korean app interfaces that follow the system language. Obsidian note output and shortcut names remain unchanged.
- Adopted the **MIT License**.

### Installation
- Install Morrowisp manually. History and settings from Pomodoro do not carry over, and the old app does not update to Morrowisp.
- You may quit and delete `Pomodoro.app`; its data remains in `~/Library/Containers/Jeong.Pomodoro`. See [installation and migration](Readme.md#install).

## [1.4.0] - 2026-10-16

### 추가
- **오늘의 메인 미션**: 팝오버 맨 위에 하루 한 가지를 적고 **끝냄**으로 체크합니다. 적어 두면 "이것만 끝내면 오늘은 충분해요"를 보여 주며, 끝낸 뒤에도 고칠 수 있습니다. 로컬 자정에는 새 칸이 비고 지난 미션은 날짜별로 남습니다.
- **보상 목록**: 작은 · 중간 · 큰 보상을 설정 > 타이머에서 더하고, 지우고, 이름을 바꿉니다. 처음에는 크기별 예시가 있으며 팝오버 보상 메뉴에서 지난 보상과 함께 고를 수 있습니다.
- **오늘 요약**: 팝오버 아래에 "오늘 집중 N번 · M분 · 연장 K번"과 가장 많이 적은 할 일을 보여 줍니다. 기록이 없으면 "오늘 첫 집중을 시작해 볼까요"를 보여 줍니다.
- **주간 간단 회고**: 기록 창의 "이번 주" 표에 오늘을 포함한 지난 7일의 미션 · 끝냄 여부 · 집중 수 · 집중 분을 보여 줍니다. "이번 주에 도움이 된 것"은 로컬 시간대의 ISO 주별로 저장합니다.
- 네 기능은 설정 > 타이머 > "전환 관리"를 켰을 때만 보입니다. 점수나 목표 비교 없이 적은 글과 실제 횟수 · 시간만 보여 줍니다.

### 변경
- **요약 집계**: 완료 횟수는 끝까지 마친 집중만 세고, 집중 분은 중간에 그만둔 기록도 실제 집중한 시간만큼 합친 뒤 분으로 내립니다. 자정을 걸친 세션은 끝난 날에 집계합니다. 휴식 선택을 기다리는 집중도 보이며, 연장한 집중은 한 번으로 셉니다.
- **기존 기록 호환**: SwiftData 스키마는 그대로 두고 미션 · 보상 목록 · 주별 메모 · 완료 여부는 UserDefaults의 JSON으로 저장합니다. 예전 기록에는 완료 표식이 없으므로 새 요약의 시간에는 포함하되 완료 횟수는 추측하지 않습니다. 기존 로그와 차트는 그대로 볼 수 있습니다.
- **Obsidian 미션 기록**: 연동을 켜 두면 미션을 적거나 고칠 때 그날 뽀모도로 섹션 맨 위에 들여쓴 한 줄을 갱신합니다. 끝냄 체크도 반영하며, 세션 기록과 기존 하루 통계는 보존합니다. 세션 내보내기의 날짜는 기존처럼 시작일을 따릅니다. 회고 메모는 내보내지 않습니다.

## [1.3.0] - 2026-10-15

### 추가
- **복귀**: 휴식 중(돌고 있거나, 멈췄거나, 준비만 된 휴식)에 팝오버의 **복귀 — 바로 집중 시작**을 누르면 휴식을 여기서 마치고 곧바로 집중을 시작합니다. 적어 둔 할 일 · 보상 · 다음 시작점은 그대로라 다시 적지 않아도 됩니다. 휴식은 지금까지 쉰 만큼 기록되고(시작하지 않은 휴식은 기록하지 않음), 마친 집중 수와 긴 휴식까지의 차례는 바뀌지 않습니다. 집중 시작 단축어도 실행합니다.
- **휴식 추천**: 휴식 화면에 짧고 끝이 있는 휴식 거리를 한 줄 보여 줍니다(물 한 잔 마시기, 자리에서 일어나 스트레칭, 창밖 보기 등 — 휴식마다 바뀜). 휴식 화면에 하던 일도 함께 보입니다.
- 위 둘은 설정 > 타이머 > "전환 관리"를 켰을 때만 보입니다.

### 변경
- **알림 문구**: 다그치지 않고 다음 행동을 묻게 바꿨습니다. 집중이 끝나면 "집중이 끝났어요 — 10분 더 할까요, 쉴까요?", 세션이 넘어갈 때는 "짧은 휴식이 끝났어요 — 집중을 시작합니다" 처럼 알립니다. 휴식이 끝나 집중으로 넘어갈 때는 적어 둔 다음 시작점을 "이어서: …"로 함께 보여 줍니다(전환 관리를 켰을 때). 느낌표와 "실패 · 부족" 같은 말은 쓰지 않습니다.

## [1.2.2] - 2026-10-12

### 변경
- **업데이트는 앱이 켜져 있는 동안 스스로 설치하지 않습니다.** 새 버전이 나오면 받아 두고 메뉴 막대 아이콘 오른쪽 위에 빨간 점으로 알립니다. 아이콘을 눌러 나오는 팝오버 맨 아래의 **업데이트**를 누르면 설치하고 앱을 다시 켭니다. 누르지 않고 앱을 끄면 그때 설치됩니다. (1.2.1까지는 타이머가 대기 중이고 창이 모두 닫힌 채로 1분쯤 지나면 스스로 설치하고 다시 켰습니다.)
- 설정 > 일반 > 업데이트의 "새 버전을 자동으로 받아 설치" 스위치를 없앴습니다. "자동으로 업데이트 확인"이 켜져 있으면 새 버전을 늘 받아 두기만 합니다(그 스위치를 꺼 두었더라도 받아 둡니다). 자동 확인을 끄면 받지도 않습니다.
- 곧바로 설치할 수 없는 업데이트(Sparkle이 스스로 받을 수 없는 것 등)는 알림 배너 대신 같은 점으로 알리고, **업데이트**를 누르면 안내 창이 뜹니다. 앱을 막 켰을 때에도 안내 창을 스스로 띄우지 않습니다.
- 참고: 1.2.1에서 이 버전으로 올라올 때는 1.2.1의 방식대로 설치됩니다 — "새 버전을 자동으로 받아 설치"를 켜 두었다면 조용한 때에 스스로, 꺼 두었다면 알림이나 안내 창을 보고 직접. 바뀐 동작은 그다음 업데이트부터 보입니다.

### 제거
- 받아 둔 업데이트를 "조용한 때"에 스스로 설치하던 동작, 그 설치가 집중을 끊지 않도록 종료를 미루던 동작.

## [1.2.1] - 2026-10-10

### 추가
- **지난 할 일·보상에서 고르기**: 팝오버의 할 일 칸과 보상 칸 옆 단추를 누르면, 지난 집중에 적었던 글을 최근 것부터 다섯 개까지 보여 주고 고른 것을 칸에 넣습니다. 고를 것이 없으면(적어 둔 기록이 없거나, 지난 글이 지금 칸에 적힌 글뿐이면) 단추가 보이지 않습니다.
- **기록 창에서 적은 글 보기**: 집중 기록의 줄마다 그때 적은 할 일·보상·다음 시작점과 연장 횟수를 함께 보여 줍니다. "전환 관리"를 꺼 두면 보이지 않습니다.

### 변경
- 설정 > 일반 > 업데이트: "자동으로 업데이트 확인"을 끄면 "새 버전을 자동으로 받아 설치" 스위치가 잠기고, 받아 둔 업데이트도 스스로 설치하지 않습니다(단추를 누르거나 앱을 끌 때 설치됩니다). 1.2.0에서는 이때 스위치를 켤 수 있었지만 곧 다시 꺼졌습니다.
- 받아 둔 업데이트의 설치를 시작하면 단추가 "설치하는 중…"으로 바뀌고, 앱이 곧 꺼졌다 다시 켜진다고 알려 줍니다.

## [1.2.0] - 2026-10-10

### 추가
- **할 일·보상 적기**: 집중을 시작하기 전(또는 집중 중)에 팝오버에서 할 일과 끝나면 받을 보상을 적을 수 있습니다. 비워 두어도 시작됩니다.
- **집중이 끝났을 때 선택**: 끝까지 마친 집중은 저절로 넘어가지 않고 **휴식 시작 / 10분 더 집중** 중 하나를 고를 때까지 기다립니다. 메뉴 바에는 🔔 "선택"이 표시됩니다.
- **다음 시작점**: 선택 화면에서 다음에 이어서 시작할 자리를 적어 두면, 휴식 중과 다음 집중에서 다시 보여 줍니다. 앱을 다시 켜도 남습니다.
- **Obsidian 기록**: 할 일·보상·다음 시작점·연장 시간을 집중 기록 줄 아래에 들여쓴 줄로 함께 남깁니다. 기록 줄과 하루 통계의 형식은 그대로입니다.
- **단축어 연동**: 집중이 시작할 때와 끝날 때 단축어 앱의 단축어를 실행합니다(설정 > 단축어에 이름을 적음). 연장하면 시작 단축어를, 건너뛰기·초기화·종료로 집중을 그만둘 때도 끝 단축어를 실행합니다. ([가이드](docs/SHORTCUTS.md))
- **자동 업데이트**: 새 버전이 나오면 앱이 스스로 확인해 받아 설치합니다([Sparkle](https://sparkle-project.org) 사용). 설치하면 앱이 꺼졌다 켜지므로, 타이머가 대기 중이고 팝오버와 창이 모두 닫힌 채로 1분쯤 지났을 때만 스스로 설치합니다. 그 전에 앱을 끄면 그때 설치됩니다. 설정 > 일반 > 업데이트에서 자동 확인과 자동 설치를 끄거나, "지금 확인"과 "지금 설치하고 다시 켜기"를 누를 수 있습니다.
- **릴리스**: GitHub 릴리스에서 앱(zip)을 받을 수 있습니다. ([설치](Readme.md#설치), [릴리스 만드는 법](docs/RELEASE.md))
- **끄기**: 설정 > 타이머 > "전환 관리"를 끄면 할 일·보상 칸과 선택 화면이 없어지고, 메모도 남기지 않으며, 예전처럼 동작합니다. (적어 둔 글은 지워지지 않고 다시 켜면 보입니다.)

### 변경
- 선택을 기다린 집중의 종료 시각은 고른 때가 아니라 시간이 다 된 때로 기록됩니다(절전으로 늦게 깨어나도 같습니다). 연장을 고르기까지 기다린 시간은 정지 시간으로 셉니다.
- 연장한 집중은 원래 시간을 이미 채웠으므로, 연장 중에 건너뛰어도 마친 집중으로 셉니다.
- 집중 기록을 지우면 딸린 메모도 함께 지웁니다.
- 팝오버 높이가 내용에 따라 달라집니다.
- 집중 도중에 앱을 종료하면, 끝 단축어의 실행 요청이 넘어갈 때까지 종료를 최대 2초 미룹니다.

### 참고
- 자동 업데이트를 위해 앱이 네트워크에 나갈 수 있게 됐습니다(업데이트 확인과 내려받기에만 씁니다). 받은 업데이트는 서명(EdDSA)이 맞을 때만 설치합니다.
- 앱은 Apple 공증을 받지 않았습니다. 처음 받아 열 때 macOS가 막으면 [설치](Readme.md#설치)의 안내를 따릅니다. 그 뒤의 업데이트는 앱이 스스로 합니다.
- 할 일·보상·다음 시작점은 집중 기록과 다른 저장소 파일(`Transitions.store`)에 둡니다. 집중 기록 저장소는 바뀌지 않으므로 예전 버전으로 돌아가도 기록이 그대로 열립니다.

## [1.1.0] - 2026-06-11

### 추가
- **설정 창 추가** (메뉴 바 팝오버 → ⚙️): 타이머 / 알림 / Obsidian / 일반 탭
- **알림음 선택**: macOS 시스템 사운드 14종 + 끄기, 미리 듣기 지원
- **세션 자동/수동 전환 설정**: 집중→휴식, 휴식→집중을 각각 자동 시작하거나 직접 시작하도록 선택 가능
- **Obsidian 데일리 노트 연동**: 세션이 끝날 때마다 `yyyy-MM-dd.md`에 초 단위 기록 + 하루 통계(항상 1줄 유지) 자동 작성
- **긴 휴식 간격 설정** (집중 N회마다 긴 휴식)
- **메뉴 바에 남은 시간 표시** 옵션
- **로그인 시 자동 실행** 옵션
- 팝오버에 긴 휴식까지의 사이클 점 표시

### 수정
- 절전 모드 등으로 타이머가 실제 시간보다 늦게 가던 문제 (벽시계 기준 계산으로 변경)
- 로그의 종료 시각에 일시정지 시간이 반영되지 않던 문제
- UTC 기준 날짜 그룹핑으로 오전 9시(KST) 이전 기록이 전날로 분류되던 문제
- 대기 중 집중 시간 설정을 바꿔도 표시 시간이 갱신되지 않던 문제
- 알림 배너 소리와 앱 알림음이 동시에 재생되던 문제

### 제거
- 사용되지 않는 Xcode 템플릿 코드(ContentView, Item)

## [1.0.0]

- 최초 버전: 뽀모도로 타이머, 메뉴 바 진행 표시, 세션 로그, 주간/월간/전체 통계 차트, 세션 종료 알림
