# Fire TV Remote for macOS

Fire TV Stick 4K 付属の Alexa 音声認識リモコンを、macOS 用のワイヤレスマイク兼コントローラーとして使うためのプロジェクトです。現在は CLI で、ボタン取得と音声の WAV 保存まで実装しています。

## 必要なもの

- Apple Silicon Mac / macOS 13 以降 / Xcode
- `brew install opus`
- macOS の Bluetooth 設定でペアリング済みのリモコン
- 実行元のターミナルに対する「入力監視」の権限

root 権限、SIP の無効化、非公開 API は使いません。

## 使い方

```sh
swift build
swift test

.build/debug/fireremote probe                 # デバイス・権限・HID Descriptor を表示
.build/debug/fireremote listen                # Report とボタンイベントを表示
.build/debug/fireremote record --out test     # 音声ボタンを押している間を録音
.build/debug/fireremote decode captures/test.bin out.wav

.build/debug/fireremote devices               # オーディオデバイスの一覧
.build/debug/fireremote stream --device "BlackHole 2ch"   # 音声を指定デバイスへ出力
.build/debug/fireremote replay captures/test.bin --device "BlackHole 2ch"   # 経路の検証用
.build/debug/fireremote capture-input --device "BlackHole 2ch" --out in.wav # 経路の検証用
```

`stream` の出力先は `--device` での指定が必須です。システムの既定デバイスは変更しません。他のアプリでは、入力デバイスとして BlackHole を選びます。

`record` は音声ボタンを離すと終了し、`captures/` に `.wav` と生 Report の `.bin` を保存します。`captures/` には音声が残るため、Git の管理対象外にしています。

`--seize` を付けるとデバイスを占有モードで開きます(未検証)。付けない場合、ボタン入力は Mac 側にも通常のキー入力として届きます。

## 構成

| パス | 役割 |
|---|---|
| `Sources/RemoteCore/HIDRemote.swift` | IOHIDManager によるデバイス接続、Report 受信、マイク制御 |
| `Sources/RemoteCore/HIDReportDescriptor.swift` | HID Descriptor の解析 |
| `Sources/RemoteCore/RemoteProfile.swift` | 機種ごとの差分(`RemoteProfile`)、ボタン判定、音声ボタンとマイクの連動 |
| `Sources/RemoteCore/OpusDecoder.swift` | libopus のラッパー |
| `Sources/RemoteCore/VoiceSession.swift` | ボタン監視、マイク連動、デコードのまとめ |
| `Sources/RemoteCore/PCMOutput.swift` | 指定デバイスへの PCM 出力 |
| `Sources/RemoteCore/AudioDevices.swift` | オーディオデバイスの列挙、検証用の入力録音 |
| `Sources/RemoteCore/Files.swift` | WAV 書き出し、生 Report の記録、音声パケットの統計 |
| `Sources/fireremote/main.swift` | CLI |

別のリモコンに対応するときは `RemoteProfile` を実装します。

## アクセス方式

公開 API の **IOHIDManager / IOHIDDevice** を使います。macOS はこのリモコンを `IOHIDUserDevice` として公開し、Descriptor にも音声用の Report が含まれているため、既存のペアリングと Bluetooth 接続を維持したまま読み書きできました。CoreBluetooth と HCI への直接アクセスは使っていません。

## 実機で確認した仕様

対象: VID `0x0171` / PID `0x042F` / FW `53305501` / macOS 26.2(2026-11-02 に1回録音)

| 項目 | 結果 |
|---|---|
| 音声データ | Input Report `0xF0`、payload 80B、TOC は常に `0xB8` |
| マイク制御 | Output Report `0xF2`。`0x01` で開始、`0x00` で停止(どちらも SetReport 成功) |
| 手順 | 音声ボタンの押下(`0x02` の `21 02`)を受けてから `0xF2=0x01` を送信 |
| 音声 | Opus 16kHz mono として 123 パケットすべてデコード成功(2.46 秒) |
| 到着間隔 | 間隔20ms換算の推定欠落 0、最大間隔 43.2ms |
| 権限 | `RequiresTCCAuthorization = True`。今回の環境は入力監視が許可済み |

その他の Report(Descriptor 上の定義のみ、内容は未確認): `0x03`(1B)、`0xEF`(3B)、`0xF1`(3B)、`0xF3`(出力 10B)

### ボタン

押下と解放の両方を確認済み:

| ボタン | Report | コード |
|---|---|---|
| 上 / 下 / 左 / 右 | `0x01` | `52` / `51` / `50` / `4F` |
| 決定 | `0x01` | `58` |
| 戻る | `0x01` | `F1` |
| 再生・停止 | `0x02` | `CD 00` |
| 音声 | `0x02` | `21 02` |

未確認(コード表は fire-remote-client の値): ホーム、メニュー、ミュート、音量、早送り、巻き戻し、TV、アプリショートカット。

### 音声経路(リモコン → `stream` → BlackHole 2ch → 入力側で録音)

| 項目 | 結果 |
|---|---|
| 発話 | 2回連続で成功(13.3 秒、6.4 秒) |
| パケット | 985 個(19.7 秒相当)、デコードエラー 0 |
| 途切れ | 入力側の音声に 5ms 以上の無音なし |
| 既定の入出力デバイス | 変更なし |
| 音声ボタン押下からマイク有効化の完了まで | 約 30ms(話してから届くまでの遅延は未計測) |

## 未検証・既知の制限

- 録音した音声を人の耳で確認した結果は未記録です(信号レベルは発話らしい変化を確認済み)。
- 約 13 秒を超える録音と、話してから届くまでの遅延は未計測です。
- 欠落の値は到着時刻からの推定です。payload 内にシーケンス番号があるかは確認していません。
- `--seize` は未検証です。
- 他のアプリで BlackHole をマイクとして選ぶ確認はしていません(音声が届くことは `capture-input` で確認)。
- 2026-11-02 の確認中に `bluetoothd` が1回クラッシュしました(SIGSEGV)。原因は不明です。リモコンは決定ボタンを押すと再接続できました。
- キー割り当て(Phase 6)以降は未実装です。

## 参考

- [fire-remote-client](https://github.com/justanotheruseer/fire-remote-client)(MIT): プロトコルとボタンのコード表を参考にしました。
- [SayAll / remote-mic-app](https://github.com/HD838A/remote-mic-app)(GPL-3.0): 設計資料のみ確認し、コードは流用していません。
- [libopus](https://opus-codec.org/)(BSD): 動的リンクで使用します。
