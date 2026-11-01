English | [한국어](Readme.ko.md)

[Getting started guide](docs/GUIDE.md)

# Morrowisp — a calm Pomodoro timer for macOS

A calm macOS menu bar Pomodoro timer for a steady daily rhythm of focus, rest, and returning to your work.

The app supports English and Korean and follows your system language. Other languages use English. Korean labels below help you find the corresponding controls.

<!-- TODO: Add a screenshot of the menu bar popover when one is available. -->

<a id="설치"></a>

## Install

1. Download `Morrowisp-<version>.zip` from [GitHub Releases](https://github.com/JeongSeongWon1116/Morrowisp/releases/latest), unzip it, and move `Morrowisp.app` to **Applications**.
2. Open the app. It is not notarized by Apple, so macOS may block it as an unidentified developer's app. In **System Settings > Privacy & Security**, choose **Open Anyway**, then open it again. The existing installation procedure also provides this Terminal command as an alternative before reopening:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Morrowisp.app
   ```

3. Later versions are downloaded automatically and indicated by a red dot on the menu bar icon. Click **Update (업데이트)** in the popover to install and reopen the app. A downloaded update also installs when you quit. It does not install on its own while the app stays open. Update controls are under **Settings > General > Updates (설정 > 일반 > 업데이트)**.

### Moving from Pomodoro (the former name)

Morrowisp 2.0.0 by **SW Square** is a new app with a new bundle identifier. Install `Morrowisp.app` manually; Pomodoro does not update to it. History and settings do not carry over. You may quit and delete the old `Pomodoro.app`. Its data remains in `~/Library/Containers/Jeong.Pomodoro` after deleting the app.

## Requirements

- macOS **14.0 or later**, as specified by the app target's deployment settings.
- Xcode **16.0 or later** to build from source, as documented in the original README.

## Features

- **Focus and rest timer.** Set focus and break durations and the interval between long breaks.
- **Settings.** Choose from 14 system notification sounds or silence, automatic or manual session transitions, and launch at login.
- **Automatic or manual transitions.** Choose separately whether focus leads into a break automatically and whether a break leads into focus automatically.
- **Transition support (전환 관리).** Write a task and an optional reward before focusing. When focus time ends, choose to start a break or continue for 10 minutes. Leave a next starting point to see when you return.
- **Return and break suggestions.** During a break, **Return (복귀)** starts focus right away with your task and next starting point intact. A short suggestion, such as a glass of water or a stretch, accompanies each break.
- **Daily main mission and reward lists (1.4).** Write one main mission for today and mark it done. Manage small, medium, and large rewards in settings and choose one from the popover.
- **Today's summary and weekly reflection (1.4).** See completed focus sessions, actual focus minutes, extensions, and the task you wrote most often today. In the history window, review missions and focus records from the past seven days and note what helped this week.
- **Reuse earlier notes.** Buttons beside the task and reward fields let you choose text from earlier sessions. History rows show the notes from each session.
- **Focus history.** Completed sessions are logged automatically.
- **Charts.** View daily focus time from your saved history.
- **Menu bar display.** See remaining time or a progress bar and the cycle leading to the next long break.
- **Notifications.** Receive a notification when focus or rest time ends.
- **Obsidian integration.** Write session durations down to the second and daily totals to daily notes. See the [Obsidian guide](docs/OBSIDIAN.md).
- **Shortcuts integration.** Run a shortcut when focus begins or ends, for example to turn Do Not Disturb on or off. See the [Shortcuts guide](docs/SHORTCUTS.md).
- **Updates.** Download new versions and install them from the menu bar or when quitting, as described above.

Enable **Transition support (전환 관리)** under **Settings > Timer (설정 > 타이머)** for task and reward notes, end-of-focus choices, return controls, break suggestions, daily missions, reward lists, today's summary, and weekly reflection.

Today's completed-session count includes only finished focus sessions. Focus minutes also include actual time from sessions ended early. Sessions crossing midnight belong to their end date in the summary; an extended focus session counts once. Older records without a completion marker contribute time, but their completion status is not guessed.

## Privacy

Your history and notes are stored locally on this Mac, using SwiftData and local preferences. Morrowisp uses the network for update checks and downloads. Automatic update checks can be turned off in settings.

If you enable Obsidian integration, the app writes to the folder you select. Shortcuts run through the macOS Shortcuts app; what they do depends on the shortcuts you choose.

## Build from source

The app uses SwiftUI, SwiftData, and Combine.

1. Clone the repository:

   ```bash
   git clone https://github.com/JeongSeongWon1116/Morrowisp.git
   ```

2. Open `Morrowisp.xcodeproj` in Xcode and select the **Morrowisp** scheme.
3. Build and run with **Cmd+R**. Development builds run from Xcode do not check for updates.

From the checkout directory, build and run tests with the shared scheme:

```bash
xcodebuild -project Morrowisp.xcodeproj -scheme Morrowisp -configuration Release -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/Morrowisp-build/dd build
xcodebuild -project Morrowisp.xcodeproj -scheme Morrowisp -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/Morrowisp-build/dd test
```

For packaging and distribution, see the [release guide](docs/RELEASE.md).

Source version: **2.1.0** (build **10**). See [CHANGELOG.md](CHANGELOG.md) for the history; older entries are in Korean.

## License

[MIT](LICENSE) — © 2026 SW Square.
