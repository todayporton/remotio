# Remotio

[English](README.md) | **日本語**

Use Bluetooth remotes as input devices on your Mac.

Bluetooth リモコンを、Mac のワイヤレスマイク兼コントローラーとして使うアプリです。対応機種は、Fire TV Stick 4K 付属の Alexa 音声認識リモコンと、Alexa 対応音声認識リモコン Pro です(Pro は互換品でのみ確認)。複数のリモコンを同時に接続でき、キーの割り当てはリモコンごとに管理します。Amazon とは関係のない非公式のプロジェクトです。

> **アルファ版です。** 動作確認は限られた環境でしか行っていません。設定の形式や動作は今後変わる場合があります。

## インストール

動作環境: Apple Silicon の Mac、macOS 13 以降、Mac とペアリング済みの対応リモコン

1. [Releases](https://github.com/todayporton/remotio/releases) から `Remotio.dmg` をダウンロードし、`Remotio.app` を「アプリケーション」フォルダへ入れます。
2. アプリを開きます。Apple の公証を受けていないので、最初はブロックされます。「完了」を押してから、システム設定 > プライバシーとセキュリティ の「このまま開く」を押し、管理者パスワードを入力します。ソースコードを確認してから開くことをおすすめします。
3. セットアップの案内が開くので、順番に進めます。権限の許可、リモコンのペアリング、仮想マイクのインストールを行います。仮想マイクのインストールには管理者パスワードが必要で、処理の間は Mac の音声が一瞬止まります。案内は、メニューバーのアイコンの「セットアップを開く…」からいつでも開けます。
4. 音声入力を使うアプリで、入力に「Remotio Microphone」を選びます。
5. メニューバーのアイコンの「設定とログを開く…」から「ボタン」を開き、音声ボタンなどにキーを割り当てます。音声入力アプリの Push-to-Talk のキーを、音声ボタンに割り当てて使えます。各ボタンの手のアイコンから、長押しと2回押しにも操作を割り当てられます。画面上部の「既定」からアプリを追加すると、そのアプリが前面にあるときだけ使う割り当てを作れます。アプリで変えていない項目は「既定」と表示され、既定の割り当てに従います。メニューの「URL を開く…」「シェルコマンドを実行…」で、キーの代わりに URL(Raycast の URL など)を開いたり、シェルコマンドを実行したりもできます。

割り当てはリモコンごとに保存されます。「ボタン」の画面上部にあるリモコン名のメニューで、編集するリモコンを選びます。設定画面が前面にあるときに別のリモコンのボタンを押しても切り替わります。初めて接続したリモコンには、最初は既存の割り当てが入ります。接続していないリモコンを選ぶと、同じメニューからその設定を削除できます。

電源ボタンにも割り当てられますが、リモコンの仕様で押してから約1秒遅れて反応するため、長押しと2回押しは使えません。

macOS の音声入力を使う場合は、システム設定 > キーボード > 音声入力 のマイクに「Remotio Microphone」を選びます。音声ボタンの操作で「音声入力」から、同じ画面の「ショートカット」と同じものを選ぶと、押したときに音声入力が始まり、離したときに終わります。

複数のリモコンを接続しているときは、マイクを使えるのは一度に1台だけです。1台が話している間は、他のリモコンの音声ボタンは無視されます。

音声はすべて Mac の中で処理され、外部へ送信しません。システムの既定の入出力デバイスは変更しません。

リモコンは、システム設定の Bluetooth でペアリングします。Fire TV とのペアリングは解除される場合があります。

設定画面とセットアップの案内は、コマンドでも開けます。

```bash
open "remotio://settings"              # 設定画面
open "remotio://settings/connection"   # ページを指定する(connection、buttons、permissions、logs)
open "remotio://setup"                 # セットアップの案内
```

### アンインストール

「接続と音声」で仮想マイクの「アンインストール」を押してから、アプリを削除します。

## 開発

ここから先は開発者向けの情報です。

### 必要なもの

- Apple Silicon Mac / macOS 13 以降 / Xcode
- `brew install opus`(ビルド時のみ)
- macOS の Bluetooth 設定でペアリング済みのリモコン
- 実行元のターミナルに対する「入力監視」の権限

root 権限、SIP の無効化、非公開 API は使いません。

### 翻訳

アプリの表示は日本語と英語に対応しています。Mac の言語設定に合わせて切り替わり、どちらでもない場合は英語になります。

翻訳ファイルは `Resources/Localization` にあり、ソースから自動で作ります。表示する文言は SwiftUI の文字列か `String(localized:)` で書きます。

```bash
scripts/update-strings.py            # 文言を抜き出し、翻訳ファイルを更新する(英語の未訳には TODO が付く)
# Resources/Localization/en-translations.py に英語の訳を追加してから
scripts/fill-english.py              # 英語の訳を反映する
scripts/update-strings.py --check    # 英語の訳の不足と、使われていない訳を確認する
```

## 使い方

```sh
swift build
swift test

.build/debug/remotio probe                 # デバイス・権限・HID Descriptor を表示
.build/debug/remotio listen                # Report とボタンイベントを表示
.build/debug/remotio record --out test     # 音声ボタンを押している間を録音
.build/debug/remotio decode captures/test.bin out.wav

.build/debug/remotio devices               # オーディオデバイスの一覧
.build/debug/remotio stream --device "Remotio Microphone"   # 音声を指定デバイスへ出力
.build/debug/remotio replay captures/test.bin --device "Remotio Microphone"   # 経路の検証用
.build/debug/remotio capture-input --device "Remotio Microphone" --out in.wav # 経路の検証用
```

キー割り当ては `run` で使います。

```sh
.build/debug/remotio run --dry-run                      # キーを送らず判定だけ表示
.build/debug/remotio run --device "Remotio Microphone"       # キー割り当て + 音声出力
.build/debug/remotio run --config keymap.json           # 割り当てを変更
```

既定の割り当ては、方向キーが矢印、決定が Return、戻るが Escape です。指定のないボタンは Mac の標準動作をそのまま通します。`none` で無効、`media:play_pause` などでメディア操作、`system:mission_control` などでシステム操作を指定できます。音声ボタンにもキーを割り当てられます。押している間はマイクが動き、キーも押され続けます。キーの解放は話し終わりの音声が届くよう 120ms 遅らせます。修飾キーだけの指定(`fn`、`ropt` など)もできます。`keymap.json` の例: `{"voice": "fn", "play_pause": "cmd+shift+p"}`。キー送信にはアクセシビリティの権限が必要です。`run` は割り当てたボタンと音声ボタンの元のキー入力を、`stream` は音声ボタン(Mac では Spotlight が開く)の元のキー入力を、`hidutil` の `UserKeyMapping` で対象リモコンに限って止めます(`--no-suppress` で無効)。

`stream` の出力先は `--device` での指定が必須です。システムの既定デバイスは変更しません。他のアプリでは、入力デバイスとして Remotio Microphone を選びます。

`record` は音声ボタンを離すと終了し、`captures/` に `.wav` と生 Report の `.bin` を保存します。`captures/` には音声が残るため、Git の管理対象外にしています。

`listen` / `record` では、ボタン入力は Mac 側にも通常のキー入力として届きます。`--seize`(占有モード)は一般ユーザーでは `kIOReturnNotPrivileged` で失敗します。

## メニューバーアプリ

```sh
scripts/build-app.sh      # build/Remotio.app を作成(libopus を同梱)
scripts/build-dmg.sh      # build/Remotio.dmg を作成
```

署名にはログインキーチェーンの自己署名証明書 `todayporton` を使います。権限はこの署名に結びつくため、証明書と秘密鍵を失うと、利用者全員に権限の再許可が必要になります。キーチェーンアクセスから `.p12` として書き出し、安全な場所に保管してください。Git には入れないでください。

配布した DMG のアプリは公証されていないため、初回の起動時に Gatekeeper にブロックされます。システム設定 > プライバシーとセキュリティ の「このまま開く」から許可します。隔離属性を付けた DMG を使い、VM で起動とドライバのインストール、アンインストールまで確認済みです。

仮想マイク `Remotio Microphone` のドライバを同梱しています。「接続と音声」の「インストール」から、`/Library/Audio/Plug-Ins/HAL` へ入れます。管理者パスワードが必要で、処理の間は Mac の音声が一瞬止まります。BlackHole は不要です。ドライバは入力の一覧にだけ出て、出力の一覧には出ません。Remotio は隠しデバイスを通して音声を渡します。BlackHole などを使いたい場合は「他の出力デバイスを使う」で選べます。ホストの実機で、出力の一覧に出ないこと、リモコンの音声がこのデバイス経由で他のアプリへ届くこと、署名が同じなら再ビルド後も権限が維持されることを確認済みです。

接続状態とマイク状態の表示、音声の出力先の選択、リモコン図を使ったキー割り当て(キーを押して記録)、権限の確認、ログ表示、ログイン時の起動の設定ができます。リモコン図は機種ごとに切り替わります。2機種の図は共通のレイアウトから作っているため、細部は実機と異なる場合があります。出力先の初期値は「なし」です。入力監視の権限が必要で、キー送信にはアクセシビリティの権限も必要です。

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
| `Sources/RemoteCore/KeyMapping.swift` | キー割り当て、キー送信 |
| `Sources/RemoteCore/KeySuppressor.swift` | 対象リモコンの元のキー入力の無効化 |
| `Sources/remotio/main.swift` | CLI |
| `Sources/RemotioApp/RemoteLayout.swift` | 機種ごとのリモコン図のボタン配置 |
| `Sources/RemotioApp/` | メニューバーアプリ |

別のリモコンに対応するときは `RemoteProfile` を実装します。同じプロトコルの別機種なら、`productIDs` に Product ID を、ボタンの表にコードを追加し、`RemoteLayout` に図を追加します。

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
| 電源 | `0x01` | `66` |

電源ボタンは、押した約1秒後に押下と解放が同時に届きます。押し続けても変わりません。

### Alexa 対応音声認識リモコン Pro(互換品)

対象: VID `0x0171` / PID `0x0425`(IOHID の製品名は `AR`)

HID Descriptor は Fire TV Stick 4K 付属のリモコンとバイト単位で同じで、音声とマイク制御も同じ手順で動きます。追加のボタンは Report `0x02` で次のコードを送ります。

| ボタン | コード |
|---|---|
| ヘッドホン | `0x0280` |
| 設定 | `0x0033` |
| チャンネル + / − | `0x009C` / `0x009D` |
| カスタム 1 / 2 | `0x027E` / `0x027F` |

純正品は未確認です。

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
- 音声ボタンの Push-to-Talk は、Amical(`Ctrl+T`)で文字入力まで確認済みです。修飾キー単体の送信は実機で未検証です。
- 元のキー入力の無効化は、方向キー、決定(カーソルが動かないことを確認)と音声ボタン(Spotlight が開かないことを確認)について実機で確認済みです。戻る、再生・停止の Mac 側の挙動は個別に見ていません。割り当てのないボタンのキー入力は Mac に届きます。
- 設定画面を操作している間は、リモコンから割り当てたキーを送りません(実機で未検証)。キー入力の待ち受け中は、他のアプリより先にキーを受け取り、後ろへ送りません(アクセシビリティの権限が必要。権限がなければアプリ内のみで受け取ります)。
- メニューバーアプリは VM で GUI のみ確認しました(リモコンなし、音声なし)。ホストでの実機確認では、リモコンからのキー送信と、BlackHole を入力にしたアプリへの音声の受け渡しが動作しました。ログイン時の自動起動の実機確認は未検証です。
- 出力先のサンプルレートが変わると音声出力を自動で再開します。再開の間に話した音声は失われます。
- 互換品の Remote Pro では、音声が途切れ途切れになり、実用になりません。リモコンは 20ms ごとに音声のパケットを作りますが、互換品からは1秒に約36個(本来は50個)しか届かず、約3〜4割が Mac に届く前に失われます。互換品だけを接続しても同じでした。失われた音声はアプリ側では取り戻せず、パケット損失補完で埋めても改善しませんでした。ボタンは問題なく使えます。純正品は未確認です。
- リモコンごとの割り当てを2台同時に接続した状態で使い分けること、2台目の音声ボタンが無視されることは、実機で未検証です。
- 元のキー入力の無効化は、シリアル番号でリモコンを区別します。シリアル番号が英数字でないリモコンは、無効化の対象から外れます。
- プログラムが異常終了すると、元のキー入力の無効化はリモコンが再接続するまで残ります。

## 参考

- [fire-remote-client](https://github.com/justanotheruseer/fire-remote-client)(MIT): プロトコルとボタンのコード表を参考にしました。
- [SayAll / remote-mic-app](https://github.com/HD838A/remote-mic-app)(GPL-3.0): 設計資料のみ確認し、コードは流用していません。
- [libopus](https://opus-codec.org/)(BSD): 動的リンクで使用します。

## ライセンス

MIT — [LICENSE](LICENSE) を参照してください。同梱するサードパーティのソフトウェア:

- libopus: BSD ライセンス
- libASPL(`Vendor/libASPL`、commit `633e0f7`): MIT ライセンス。一部に Apple のサンプルコードのライセンスが含まれます
