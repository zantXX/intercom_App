# AGENTS.md — AIエージェント引き継ぎ・開発ガイド

このファイルは、本リポジトリ（`intercom_App`）の開発経緯・設計方針・実装状況・運用ルールをまとめた引き継ぎドキュメントです。作業を開始する前に必ず一読してください。

---

## 1. プロジェクト概要と基本方針

- **目的**：スマホだけで動く「バイク用インカム風」の常時グループ音声通話アプリ（Discordのボイスチャンネルのような操作感）。
- **ネットワーク前提**：
  - 基本は **「参加者全員が同じLAN（ローカルネットワーク）にいること」** を前提とする（1台のスマホがWi-Fiテザリング親機になり、他のスマホがそこに接続する運用が基本）。
  - インターネット非依存（オフライン・0円）で動作する。
  - MultipeerConnectivity / Nearby Connections / Wi-Fi Direct / BLEブリッジは採用しない。
- **フレームワーク**：Flutter（Android先行、将来iOS拡張可能な構成）。
- **開発・検証スタイル**：
  - PC負荷軽減と実環境（音声・Wi-Fi・Bluetooth）検証のため **Androidエミュレータは使用しない**。
  - 実機2台（**Google Pixel 8a**＝ホスト・テザリング親機役、**OPPO Reno3 A**＝参加者役）を USB / ワイヤレスデバッグ（ADB）またはリリースAPKで試験する。

---

## 2. これまでの経緯と意思決定ログ（会話の要点）

### 2.1 M0〜M1（初期プロトタイプと実機1対1通話の達成）
- 要件定義書（`docs/requirements_definition.md`）および方式設計書（`docs/architecture.md`）を策定。
- ホスト端末内で動く組み込みWebSocketシグナリングサーバー（ポート `47800`）＋ WebRTC P2P音声通信（`iceServers: []`）を実装し、実機2台（Pixel 8a / Reno3 A）でIP直接入力による1対1音声通話の動作を確認済み。

### 2.2 M1実機レビューでのフィードバックと決定事項
M1の動作確認後、以下の5点の改善・質問があり、それぞれの対応方針を合意・実装した。

1. **「IPを打つのが面倒なので、つなげる候補を表示してほしい」**
   - **対応（M2）**：mDNS / DNS-SD（`nsd` パッケージ、サービス種別 `_intercom._tcp`）でホストのルームをLAN上に自動公開・検出し、ホーム画面の「近くのルーム」一覧からワンタップで参加できるようにした。
2. **「以前接続した端末・アカウント情報を保持してつなぐことはできる？」**
   - **対応（M2 / F-07〜F-09）**：
     - アカウント登録不要で、初回起動時にランダムな16バイト端末ID（`deviceId`）と表示名・アイコン色を生成して端末内に永続化（`StorageService`）。
     - 一度通話した相手を `deviceId`＋表示名＋色＋前回ホストIP/ポート（`KnownPeer`）として最大20件記憶。
     - 記憶した相手のルームは一覧の最上位に **「⭐ 以前の相手」** として優先表示。
     - ホーム画面に **「最近の接続」** 一覧を表示し、mDNSで見つかっていればそのルームへ、見つからない場合も前回ホストIPへワンタップで再接続を試行可能にした。
     - 設定でON/OFFできる **「記憶した相手のルームに自動参加」**（初期値OFF）を実装。なお、自分で手動退出したルーム（`roomId`）にはその場で自動再参加しない抑止制御を入れた。
3. **「音声デバイスの切り替えができたらいい（スピーカー / Bluetoothイヤホンなど）」**
   - **対応（M4前倒し / F-20〜F-24）**：
     - 通話画面下部の出力先ボタン（および設定画面）から **スピーカー / 受話口（耳元） / 有線イヤホン / Bluetoothヘッドセット（インカム）** をボトムシートで切り替えられるようにした。
     - Androidの `AudioManager`（API 31+は `setCommunicationDevice`、API 30以下は `startBluetoothSco` / `isSpeakerphoneOn`）と `AudioDeviceCallback` を `MainActivity.kt` に実装し、Bluetoothや有線イヤホンの接続検知による自動切替・切断時の自動復帰にも対応した。
4. **「走行風などのノイズが入るはずなのでノイズキャンセル・ゲートを入れたい」**
   - **対応（F-32, F-33, F-35, F-36）**：
     - WebRTC音声トラックの **ノイズ抑制（NS）・エコー除去（AEC）・自動ゲイン調整（AGC）** を設定画面からON/OFF可能にした（既定はすべてON）。
     - Opus SDPパラメータに `usedtx=1;useinbandfec=1;maxaveragebitrate=32000;stereo=0` を付与。
     - **ノイズゲート（入力感度しきい値スライダー：1%〜35%）** を実装。しきい値未満の小音量ノイズ（話していない時の風切り音など）を遮断する。
     - **マイク＆録音テスト機能（F-35, F-36）** を設定画面に実装。リアルタイムの入力レベルメーターとゲート開閉状態（🟢送信／🛡️遮断）を確認しながら、自分の声を最大15秒録音して、ノイズ抑制＋ノイズゲート適用後の音が実際にどう聞こえるかその場で再生確認できるようにした。
5. **「インターネットにつないで通話するには何かリソースが必要？」**
   - **対応（`docs/architecture.md` §12）**：
     - 実装はローカルモードを優先しつつ、将来の拡張として 4G/5G モバイル回線経由の通話に必要な3つの外部リソース（①シグナリングサーバー、②STUNサーバー、③携帯キャリアNAT越えに事実上必須となるTURN中継サーバー）の通信量・無料枠/コスト目安と、既存の `SignalingService` / `WebRTCService` を最小限の変更で切り替える設計を `docs/architecture.md` §12 に追記した。

### 2.3 友達への配布とiPhone対応について
- **Androidの配布**：
  - Google Playストア登録不要で、リリースビルドしたAPKを共有するだけでインストール可能。
  - Gitでも履歴・配布ファイルを残せるよう、`.gitignore` に `!releases/*.apk` を設定し、64bit ARM向けの軽量リリースAPKを `releases/intercom-app-release.apk`（約30MB）として配置済み。
- **iPhone（iOS）の扱い**：
  - Windows単体ではXcode制約によりiOSビルド不可、かつiOSは野良APKのような直接配布ができない。
  - 将来iOS対応する場合は、GitHub Actions / Codemagic 等のクラウドmacOS環境＋TestFlight（Apple Developer Program）を使う方針。

---

## 3. ディレクトリ・ファイル構成

```text
intercom_App/
├─ AGENTS.md                           # 本ドキュメント（AI引き継ぎ用）
├─ README.md                           # プロジェクト概要
├─ .gitignore                          # releases/*.apk のみ例外的にGit追跡を許可
├─ docs/
│  ├─ requirements_definition.md       # 要件定義書（F-01〜F-50, N-01〜N-09, Q-01〜Q-05）
│  ├─ architecture.md                  # 方式設計書（§1〜§12：インターネット通話設計含む）
│  └─ archive/
│     └─ initial_prototype_design.md   # 旧プロトタイプ設計（アーカイブ）
├─ releases/
│  ├─ README.md                        # APKのインストール・更新手順
│  └─ intercom-app-release.apk         # 実機配布用リリースAPK（arm64-v8a）
└─ app/                                # Flutterプロジェクト本体（作業ディレクトリ）
   ├─ pubspec.yaml
   ├─ lib/
   │  ├─ main.dart                     # エントリポイント（Storage/Discovery/CallController初期化）
   │  ├─ models/
   │  │  ├─ profile.dart               # 自分のプロフィール（deviceId, name, color）
   │  │  ├─ peer.dart                  # 通話相手（PeerInfo）と記憶した相手（KnownPeer）
   │  │  └─ room.dart                  # mDNSルーム情報（RoomInfo / RoomAdvert）
   │  ├─ services/
   │  │  ├─ call_controller.dart       # ルーム作成・参加・hello/welcome/reject・自動参加の統括
   │  │  ├─ signaling_service.dart     # 組み込みWebSocketサーバー（ホスト）＆クライアント（connId管理）
   │  │  ├─ webrtc_service.dart        # WebRTC音声P2P、Opus SDP調整、統計取得、ノイズゲート
   │  │  ├─ discovery_service.dart     # nsdによるmDNS公開（advertise）と検出（browsing）
   │  │  ├─ audio_device_service.dart  # 音声出力切替（BT自動切替）＆録音テスト（MethodChannel連携）
   │  │  ├─ storage_service.dart       # SharedPreferences永続化（プロフィール・記憶した相手・音声設定）
   │  │  └─ network_info.dart          # 自端末のIPv4アドレス一覧取得
   │  └─ screens/
   │     ├─ home_screen.dart           # ホーム画面（ルーム作成・近くのルーム・最近の接続・手動IP入力）
   │     ├─ room_screen.dart           # 通話画面（話者緑リング・72dp大ボタン・出力先シート・品質指標）
   │     ├─ settings_screen.dart       # 設定画面（プロフィール・出力先・ノイズゲート・録音テスト・履歴管理）
   │     └─ intercom_screen.dart       # 各画面の再エクスポート
   └─ android/app/src/main/
      ├─ AndroidManifest.xml           # 音声・Bluetooth・mDNS（CHANGE_WIFI_MULTICAST_STATE）権限
      └─ kotlin/com/intercom/intercom_app/
         └─ MainActivity.kt            # MethodChannel "intercom/audio"（出力切替・BT監視・WAV録音・JSON永続化）
```

---

## 4. よく使うコマンドと実機インストール手順

### 4.1 静的解析（`app/` ディレクトリで実行）
> **注意**：Windows の開発者モードが無効な環境で `flutter pub get` が走るとプラグインの symlink 作成エラーになるため、`pubspec.yaml` を変更していない場合は **`--no-pub`** を付けること。

```powershell
flutter analyze --no-pub
```

### 4.2 配布用リリースAPKのビルドと `releases/` への反映
コードを変更したら、以下の単一コマンドでビルドし、`releases/intercom-app-release.apk` を最新化してください。
```powershell
# 1. app/ ディレクトリでビルド
flutter build apk --release --split-per-abi --no-pub

# 2. リポジトリルートで releases/ へコピー
Copy-Item app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk releases\intercom-app-release.apk -Force
```

### 4.3 実機2台（Pixel 8a / OPPO Reno3 A）へのインストール・起動
- **端末シリアル / ワイヤレスデバッグ情報**：
  - **Google Pixel 8a**：USBシリアル `42261JEKB13039` ／ ワイヤレスADBポート `5555`（例：`10.29.214.213:5555`）
  - **OPPO Reno3 A**：USBシリアル `1f7d8c64`（モデル `CPH2013`） ／ ワイヤレスADBポート `5556`（例：`10.29.214.211:5556`）

- **ユーザーの PowerShell から直接インストール＆起動するスクリプト（推奨・最速）**：
  AI の `run_command` 承認待ちロックを避けるため、実機へのADB転送はユーザー自身の PowerShell（`c:\Users\zant\git_project\intercom_App`）で以下を実行してもらうのが最も確実・高速である。
  ```powershell
  $apk = "c:\Users\zant\git_project\intercom_App\releases\intercom-app-release.apk"
  $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

  # USB接続中の Pixel 8a に入れて起動する場合
  & $adb -s 42261JEKB13039 install -r $apk
  & $adb -s 42261JEKB13039 shell monkey -p com.intercom.intercom_app -c android.intent.category.LAUNCHER 1

  # USB接続中の OPPO Reno3 A に入れて起動する場合
  & $adb -s 1f7d8c64 install -r $apk
  & $adb -s 1f7d8c64 shell monkey -p com.intercom.intercom_app -c android.intent.category.LAUNCHER 1
  ```
- **ワイヤレスADBで行なう場合（USBで `tcpip 5555` / `5556` 有効化後）**：
  ```powershell
  $apk = "c:\Users\zant\git_project\intercom_App\releases\intercom-app-release.apk"
  $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
  & $adb -s 10.29.214.213:5555 install -r $apk
  & $adb -s 10.29.214.211:5556 install -r $apk
  & $adb -s 10.29.214.213:5555 shell monkey -p com.intercom.intercom_app -c android.intent.category.LAUNCHER 1
  & $adb -s 10.29.214.211:5556 shell monkey -p com.intercom.intercom_app -c android.intent.category.LAUNCHER 1
  ```

---

## 5. 今後のマイルストーン・残タスク

| マイルストーン | 状態 | 内容 |
|---|---|---|
| **M0 / M1** | ✅ 完了 | 環境構築、1対1 WebRTC P2P音声通話（実機2台で検証済み） |
| **M2** | 🟡 実機検証中 | ルーム作成・mDNS自動検出・プロフィール・最近の接続（⭐）・自動参加（Reno3 Aで起動確認済み） |
| **M4（前倒し）** | 🟡 実機検証中 | 音声出力デバイスの切り替え（スピーカー/受話口/有線/Bluetooth自動切替） |
| **ノイズ対策** | 🟡 実機検証中 | ノイズ抑制・ノイズゲート（しきい値調整）＋マイク＆録音聴き返しテスト |
| **M3** | 未着手 | 3〜4人フルメッシュ通話への拡張（`peerId` 辞書順でのoffer制御）、参加者長押しでの個別音量調整（0〜200%） |
| **M5** | 未着手 | バックグラウンド常駐（Android Foreground Service `microphone`、`PARTIAL_WAKE_LOCK`、`WifiLock`、常駐通知からのミュート・退出）＋切断時の自動再接続 |
| **M6** | 未着手 | テザリング＋実走テスト（距離測定 Q-01〜Q-05、風切り音の実走評価） |

---

## 6. AIエージェント向け運用ルール（ドキュメント・APKの更新基準）

別のAIや新しいセッションへいつでも引き継げる状態を維持するため、以下の **4つのタイミング（トリガー）** に該当したら、ユーザーから個別に指示されなくても自律的にドキュメントおよび成果物を更新してから作業完了を報告すること。

| # | 更新トリガー（いつ） | 更新対象（なにを） | 更新内容（どうする） |
|---|---|---|---|
| **1** | **方針・仕様の決定／変更時**<br/>（ユーザーとの対話で新しい仕様・設計方針・優先順位が決まったとき） | `AGENTS.md`（§2 意思決定ログ）<br/>`docs/requirements_definition.md`<br/>`docs/architecture.md` | 合意した背景（ユーザーの要望・課題）と決定した解決方針を追記・更新する |
| **2** | **ファイルの追加・削除・構成変更時**<br/>（新しいDartファイルやネイティブコードを追加・削除・統合したとき） | `AGENTS.md`（§3 ディレクトリ構成） | ツリー図と各ファイルの1行説明を最新の状態に同期する |
| **3** | **機能実装・バグ修正の完了時**<br/>（コード変更を伴う1つの作業単位が完了し、`flutter analyze --no-pub` が通過したとき） | `AGENTS.md`（§2・§5 残タスク）<br/>`README.md`<br/>`releases/intercom-app-release.apk` | ① マイルストーンの進捗状態を更新する<br/>② 変更がアプリ動作に影響する場合はリリースAPKを再ビルドして `releases/intercom-app-release.apk` を最新化する（※ユーザーが「ビルド不要」と明示した場合を除く） |
| **4** | **実機テスト・検証結果の判明時**<br/>（実機で動作確認・距離測定・不具合確認を行ったとき） | `AGENTS.md`（§2・§5・§7）<br/>`docs/architecture.md`（§11 検証項目） | 確認できた動作結果、発生した端末固有の事象、およびその対処内容を記録する |

---

## 7. トラブルシューティング・再発防止ルール（必読）

過去に実際に発生したトラブルと、その再発防止ルールです。**AIエージェントは以下の禁止事項・対策を厳守してください。**

### 7.1 `run_command` タスクの承認待ちフリーズ（10秒タイムアウト問題）
- **発生事象**：
  - この Windows 環境（24H2未満）では `exebox` サンドボックスが動作しないため、`run_command` は `BypassSandbox: true`（要ユーザー承認）で実行される。
  - `run_command` の `WaitMsBeforeAsync`（最大10秒）以内に承認されないままバックグラウンドタスクに移行すると、**UI上から承認ボタンが押せなくなり、ログ0バイトのままタスクが永久に固まる**。
  - さらに `;` や `&&`、`|`、`$変数` を使った複合コマンドは「常に許可（Always Allow）」のプレフィックス一致が無効化されるため、毎回手動承認が必要になり高確率でこのロックを引き起こす。
- **再発防止ルール**：
  1. **`run_command` で `;` や `&&` による複数コマンド連結を行わない**。必ず自動承認が効く単一コマンド（`flutter analyze --no-pub`、`flutter build apk --release --split-per-abi --no-pub`、`Copy-Item ...`）で1つずつ実行する。
  2. **ADBコマンドでタスクがバックグラウンド化（固まり）した場合は即キャンセルし、何度も `run_command` でリトライしない**。代わりに §4.3 の PowerShell コマンドブロックをユーザーに提示し、手元の PowerShell で実行してもらう。

### 7.2 実機起動時のスプラッシュ画面フリーズ（`shared_preferences_android` クラッシュ）
- **発生事象**：
  - `shared_preferences_android` プラグインが Android Gradle Plugin 9 / Kotlin Coroutines の ABI 不一致およびリリースビルド時の R8 難読化によって `java.lang.NoSuchMethodError: SharedPreferencesApiRegistrar.getAll` を投げ、`runApp()` 到達前にクラッシュしてスプラッシュ画面で止まった。
- **再発防止ルール**：
  1. **`shared_preferences` パッケージは使用しない**（`GeneratedPluginRegistrant.java` にも登録しない）。永続化はすべて `MainActivity.kt` の `MethodChannel("intercom/audio")`（`readStore` / `writeStore` → `filesDir/intercom_store.json`）経由で行う。
  2. **`main.dart` の `main()` では `runApp()` の前に `await` を置かない**。必ず同期的に `runApp(const IntercomApp())` を呼び、初期化は Widget 内の非同期処理で行う。
  3. **`android/app/build.gradle.kts` の `release` ビルドでは `isMinifyEnabled = false` / `isShrinkResources = false` を維持する**（WebRTC や mDNS プラグインの JNI メソッド消失防止）。

### 7.3 Windows での `flutter pub get` シンボリックリンクエラー
- **発生事象**：
  - Windows の「開発者モード」がOFFの環境で `flutter pub get` が走ると、`Building with plugins requires symlink support` で停止する。
- **再発防止ルール**：
  - `flutter analyze` や `flutter build` を行う際は、常に **`--no-pub`** オプションを付与する。


