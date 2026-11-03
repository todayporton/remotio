# Remotio

**English** | [日本語](README.ja.md)

Use Bluetooth remotes as input devices on your Mac.

Remotio turns a Bluetooth remote into a wireless microphone and controller for your Mac. It currently supports the Alexa Voice Remote that comes with the Fire TV Stick 4K. This is an unofficial project and is not affiliated with Amazon.

> **This is an alpha release.** It has only been tested in a limited set of environments. The settings format and behavior may change.

## Installation

Requirements: an Apple silicon Mac, macOS 13 or later, and a supported remote paired with the Mac

1. Download `Remotio.dmg` from [Releases](https://github.com/todayporton/remotio/releases) and move `Remotio.app` to the Applications folder.
2. Open the app. It isn't notarized by Apple, so macOS blocks it the first time. Click Done, then click Open Anyway in System Settings > Privacy & Security and enter an administrator password. We recommend reviewing the source code before you open it.
3. The setup guide opens. Work through it in order: grant permissions, pair the remote, and install the virtual microphone. Installing the virtual microphone needs an administrator password, and the Mac's audio pauses briefly while it installs. You can open the guide at any time with Open Setup… from the menu bar icon.
4. In the app you want to dictate into, choose "Remotio Microphone" as the input.
5. Choose Open Settings and Logs… from the menu bar icon, open Buttons, and assign keys to the voice button and other buttons. You can assign a dictation app's push-to-talk key to the voice button. Use the hand icon next to each button to also assign actions to a long press and a double press. Add an app from the Global menu at the top of the page to create assignments that apply only while that app is in front. Items you haven't changed for an app show "Global" and follow the global assignments. With Open URL… and Run Shell Command… in the menu, a button can open a URL (such as a Raycast URL) or run a shell command instead of sending a key.

To use macOS Dictation, choose "Remotio Microphone" as the microphone in System Settings > Keyboard > Dictation. In the voice button's menu, under Dictation, choose the same shortcut as Shortcut on that settings page. Dictation then starts when you press the button and stops when you release it.

All audio is processed on your Mac and is never sent anywhere. Remotio doesn't change the system's default input and output devices.

Pair the remote in the Bluetooth section of System Settings. This may unpair it from your Fire TV.

You can also open the settings window and the setup guide from the command line.

```bash
open "remotio://settings"              # Settings window
open "remotio://settings/connection"   # A specific page (connection, buttons, permissions, logs)
open "remotio://setup"                 # Setup guide
```

### Uninstalling

Click Uninstall for the virtual microphone in Connection & Audio, then delete the app.

## Development

The rest of this document is for developers.

### Requirements

- Apple silicon Mac / macOS 13 or later / Xcode
- `brew install opus` (needed only to build)
- A remote paired in the macOS Bluetooth settings
- Input Monitoring permission for the terminal you run from

Remotio doesn't use root privileges, doesn't require disabling SIP, and doesn't use private APIs.

### Translation

The app is available in Japanese and English. It follows the Mac's language settings and falls back to English for other languages.

The translation files are in `Resources/Localization` and are generated from the source. Write user-facing text as SwiftUI strings or with `String(localized:)`.

```bash
scripts/update-strings.py            # Extract strings and update the translation files (missing English gets a TODO)
# Add English translations to Resources/Localization/en-translations.py, then
scripts/fill-english.py              # Apply the English translations
scripts/update-strings.py --check    # Check for missing English and unused translations
```

## Usage

```sh
swift build
swift test

.build/debug/remotio probe                 # Show devices, permissions, and the HID descriptor
.build/debug/remotio listen                # Show reports and button events
.build/debug/remotio record --out test     # Record while the voice button is held
.build/debug/remotio decode captures/test.bin out.wav

.build/debug/remotio devices               # List audio devices
.build/debug/remotio stream --device "Remotio Microphone"   # Send audio to a device
.build/debug/remotio replay captures/test.bin --device "Remotio Microphone"   # For testing the audio path
.build/debug/remotio capture-input --device "Remotio Microphone" --out in.wav # For testing the audio path
```

Use `run` for key assignments.

```sh
.build/debug/remotio run --dry-run                      # Show what would be sent without sending keys
.build/debug/remotio run --device "Remotio Microphone"       # Key assignments + audio output
.build/debug/remotio run --config keymap.json           # Use different assignments
```

By default, the direction buttons send the arrow keys, select sends Return, and back sends Escape. Buttons without an assignment keep the Mac's standard behavior. Use `none` to disable a button, values such as `media:play_pause` for media controls, and values such as `system:mission_control` for system actions. The voice button can have a key too: while you hold it, the microphone is on and the key stays pressed. The key release is delayed by 120 ms so the end of your speech still arrives. You can also assign a modifier key alone (`fn`, `ropt`, and so on). Example `keymap.json`: `{"voice": "fn", "play_pause": "cmd+shift+p"}`. Sending keys requires Accessibility permission. `run` stops the original key input of assigned buttons and the voice button, and `stream` stops the original key input of the voice button (which opens Spotlight on a Mac). Both use `hidutil`'s `UserKeyMapping`, limited to the remote (`--no-suppress` turns this off).

`stream` requires an output device with `--device`. It doesn't change the system's default devices. In other apps, choose Remotio Microphone as the input device.

`record` stops when you release the voice button and saves a `.wav` and a `.bin` of raw reports in `captures/`. Because `captures/` holds audio, it is excluded from Git.

With `listen` and `record`, button presses also reach the Mac as normal key input. `--seize` (exclusive mode) fails with `kIOReturnNotPrivileged` for regular users.

## Menu bar app

```sh
scripts/build-app.sh      # Build build/Remotio.app (bundles libopus)
scripts/build-dmg.sh      # Build build/Remotio.dmg
```

The app is signed with the self-signed certificate `todayporton` in the login keychain. Permissions are tied to this signature, so if the certificate and private key are lost, every user has to grant permissions again. Export them as a `.p12` from Keychain Access and keep it somewhere safe. Don't put it in Git.

The app in the distributed DMG isn't notarized, so Gatekeeper blocks it on first launch. Allow it with Open Anyway in System Settings > Privacy & Security. Launching, installing the driver, and uninstalling it have been tested in a VM with a quarantined DMG.

The driver for the virtual microphone `Remotio Microphone` is included. Install it to `/Library/Audio/Plug-Ins/HAL` with Install in Connection & Audio. It requires an administrator password, and the Mac's audio pauses briefly while it installs. BlackHole isn't needed. The driver appears only in the input list, not the output list; Remotio passes audio through a hidden device. To use BlackHole or another device instead, choose it with Use another output device. On a real Mac, we've confirmed that the driver doesn't appear in the output list, that the remote's audio reaches other apps through it, and that permissions survive a rebuild as long as the signature stays the same.

The app shows the connection and microphone status, lets you choose the audio output, assign keys on a drawing of the remote (press a key to record it), check permissions, view logs, and open the app at login. The button layout in the drawing may not exactly match the real remote. The output defaults to None. The app needs Input Monitoring permission, and sending keys also needs Accessibility permission.

## Structure

| Path | Role |
|---|---|
| `Sources/RemoteCore/HIDRemote.swift` | Device connection through IOHIDManager, receiving reports, microphone control |
| `Sources/RemoteCore/HIDReportDescriptor.swift` | HID descriptor parsing |
| `Sources/RemoteCore/RemoteProfile.swift` | Per-model differences (`RemoteProfile`), button decoding, linking the voice button to the microphone |
| `Sources/RemoteCore/OpusDecoder.swift` | libopus wrapper |
| `Sources/RemoteCore/VoiceSession.swift` | Ties together button monitoring, the microphone, and decoding |
| `Sources/RemoteCore/PCMOutput.swift` | PCM output to a chosen device |
| `Sources/RemoteCore/AudioDevices.swift` | Listing audio devices, recording input for testing |
| `Sources/RemoteCore/Files.swift` | WAV writing, raw report recording, audio packet statistics |
| `Sources/RemoteCore/KeyMapping.swift` | Key assignments and sending keys |
| `Sources/RemoteCore/KeySuppressor.swift` | Stopping the remote's original key input |
| `Sources/remotio/main.swift` | CLI |
| `Sources/RemotioApp/` | Menu bar app |

To support another remote, implement `RemoteProfile`.

## How it accesses the remote

Remotio uses the public **IOHIDManager / IOHIDDevice** APIs. macOS exposes this remote as an `IOHIDUserDevice`, and its descriptor includes the audio reports, so Remotio can read and write it while keeping the existing pairing and Bluetooth connection. It doesn't use CoreBluetooth or direct HCI access.

## Behavior confirmed on real hardware

Device: VID `0x0171` / PID `0x042F` / FW `53305501` / macOS 26.2 (one recording on 2026-11-02)

| Item | Result |
|---|---|
| Audio data | Input report `0xF0`, 80-byte payload, TOC always `0xB8` |
| Microphone control | Output report `0xF2`. `0x01` starts and `0x00` stops (SetReport succeeds for both) |
| Sequence | Send `0xF2=0x01` after receiving the voice button press (`21 02` in `0x02`) |
| Audio | All 123 packets decoded as Opus 16 kHz mono (2.46 seconds) |
| Arrival interval | 0 estimated drops assuming 20 ms intervals, longest interval 43.2 ms |
| Permissions | `RequiresTCCAuthorization = True`. Input Monitoring was already granted in this environment |

Other reports (defined in the descriptor only; contents not examined): `0x03` (1 byte), `0xEF` (3 bytes), `0xF1` (3 bytes), `0xF3` (10-byte output)

### Buttons

Both press and release confirmed:

| Button | Report | Code |
|---|---|---|
| Up / Down / Left / Right | `0x01` | `52` / `51` / `50` / `4F` |
| Select | `0x01` | `58` |
| Back | `0x01` | `F1` |
| Play/Pause | `0x02` | `CD 00` |
| Voice | `0x02` | `21 02` |

### Audio path (remote → `stream` → BlackHole 2ch → recorded on the input side)

| Item | Result |
|---|---|
| Speech | Two takes in a row succeeded (13.3 and 6.4 seconds) |
| Packets | 985 (19.7 seconds' worth), 0 decode errors |
| Gaps | No silence of 5 ms or more in the input audio |
| Default input and output devices | Unchanged |
| From pressing the voice button to the microphone being on | About 30 ms (latency from speaking to arrival not measured) |

## Untested and known limitations

- No one has yet listened to the recorded audio and recorded the result (the signal level changes as expected for speech).
- Recordings longer than about 13 seconds and the latency from speaking to arrival haven't been measured.
- Drop counts are estimated from arrival times. We haven't checked whether the payload contains a sequence number.
- Push-to-talk on the voice button has been confirmed with Amical (`Ctrl+T`) through to text input. Sending a modifier key alone hasn't been tested on real hardware.
- Stopping the original key input has been confirmed on real hardware for the direction buttons, select (the cursor doesn't move), and the voice button (Spotlight doesn't open). The Mac's behavior for back and play/pause hasn't been checked individually. Key input from buttons without an assignment reaches the Mac.
- While you use the settings window, assigned keys aren't sent from the remote (not tested on real hardware). While waiting for a key to record, Remotio receives keys before other apps and doesn't pass them on (requires Accessibility permission; without it, only keys within the app are received).
- The menu bar app's GUI has been checked only in a VM (no remote, no audio). On a real Mac, sending keys from the remote and passing audio to an app using BlackHole as its input both worked. Opening at login hasn't been tested on real hardware.
- If the output device's sample rate changes, audio output restarts automatically. Speech during the restart is lost.
- If the program crashes, the stopped key input stays in effect until the remote reconnects.

## Credits

- [fire-remote-client](https://github.com/justanotheruseer/fire-remote-client) (MIT): Used as a reference for the protocol and the button code table.
- [SayAll / remote-mic-app](https://github.com/HD838A/remote-mic-app) (GPL-3.0): Only the design documents were reviewed; no code was reused.
- [libopus](https://opus-codec.org/) (BSD): Dynamically linked.

## License

MIT — see [LICENSE](LICENSE). Bundled third-party software:

- libopus: BSD license
- libASPL (`Vendor/libASPL`, commit `633e0f7`): MIT license. Parts are under Apple's sample code license
