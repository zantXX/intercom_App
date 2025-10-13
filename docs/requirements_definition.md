# プロトタイプ設計（概要）

**目的**：スマホアプリで「バイク用インカム風」リアルタイム音声通話を、原則ローカル（同一Wi-Fi / P2P /近接）で動かし、拡張でクラウド経由（Web）を使えるようにする。最初は4人までの低遅延通話を想定。

**基本戦略（高レベル）**

* 音声メディアは **WebRTC（Opus）ベースのP2Pメッシュ** を第一選択とする。4人程度ならメッシュ（各端末が全員に直接送る）は帯域/計算で許容でき、クラウドSFUを不要にできるため“ローカル優先”に合致。必要なら将来ローカルSFU（Raspberry Pi 等）を追加。([Stream][1])
* 端末発見／シグナリング（接続セットアップ）は **ローカル検出 + 軽量シグナリング** を採用：iOSは**MultipeerConnectivity**、Androidは**Nearby Connections / Wi-Fi Direct** を基本に、互換が必要な場面は mDNS/UDP または Bluetooth LE（制御チャネル）でブリッジ。([Apple Developer][2])
* Bluetooth は **オーディオの主運搬路には使わない**（BLE帯域不足 / プロファイル制約）。代わりに **BLEは検出・制御（ボタン、ペアリング情報共有）に利用**。ヘッドセット音声はOSが管理する（ヘッドセットはシステム経由でアプリのマイク/出力にルーティング）。
* 完全オフラインの近接（インターネット無し）でも動く設計にする（STUN等に依存しないローカルICE候補、ローカルシグナリング）。

---

# 1. アーキテクチャ図（テキスト版）

```
[Device A]  \
[Device B]   --- (local mesh via WebRTC P2P over Wi-Fi / Wi-Fi Direct) --- [Device C]
[Device D]  /
 
Discovery & signaling:
 - iOS: MultipeerConnectivity  -> exchange SDP/ICE (or act as discovery + open UDP mDNS)
 - Android: Nearby Connections / Wi-Fi Direct -> exchange SDP/ICE
 - Cross-OS: fallback to BLE-control for bootstrapping, then switch to Wi-Fi data.

Optional:
 - Local SFU on portable device (Raspberry Pi) running Pion/Janus if mesh becomes heavy.
 - Cloud SFU for remote bridging when user chooses "web mode".
```

---

# 2. コンポーネント詳細

## 2.1 ネットワーク・モード（優先順）

1. **Same Wi-Fi / infrastructure LAN** — fastest & simplest. Use WebRTC P2P, local IP candidates discovered via mDNS/UDP.
2. **Peer-to-Peer Wi-Fi / Wi-Fi Direct** — when no AP is present. Android Wi-Fi Direct API、iOSはMultipeerのP2P Wi-Fiトランスポートを活用。([Android Developers][3])
3. **Nearby/Multipeer over Bluetooth** — 発見・シグナリングに利用（実データはWi-Fiへ）。NearbyはBluetooth+Wi-Fiを組み合わせた戦略がある。([サイエンスダイレクト][4])
4. **Bluetooth（BLE）** — 音声ストリームには不採用（帯域/プロファイルのため）。BLEは小さなメタ情報（ボタン押下、招待トークン）やカスタムペアリングのために使う。

## 2.2 メディアパス

* **Media codec**: Opus (WebRTC標準)
* **Library**: libwebrtc (ネイティブiOS/Android)、もしくは WebRTC ラッパー（React Native などを使う場合）
* **Topology**: Full mesh (n*(n-1)/2 peer connections). n=4 → 6 RTCPeerConnections：実用的。([Stream][1])
* **Alternatives**: ローカルSFU（Pion/Janus）をローカルLAN内に置くと、端末負荷と上行帯域を大幅に削減可能（ただしSFUホストが必要）。([digitalsamba.com][5])

## 2.3 発見とシグナリング

* **iOS**: MultipeerConnectivity（自動発見 + 信頼できるローカルシグナリング）。([Apple Developer][2])
* **Android**: Nearby Connections API（発見 & P2P接続）。必要に応じて Wi-Fi Direct にフォールバック。([Google for Developers][6])
* **Cross-platformブリッジ（BLEを利用した具体案）**:
  iOSのMultipeerConnectivityとAndroidのNearby Connectionsは直接互換性がないため、両OSが共通して利用できるBLEを「接続確立前の情報交換チャネル」として利用する。

  **具体的なシーケンス案：**
  1. **ホスト側のBLEアドバタイズ**:
     - グループのホスト（または最初の発見要求者）が、アプリ固有のサービスUUIDを含むBLEアドバタイズを開始。
     - アドバタイズパケットには、セッションを識別するためのユニークな「ルームID」を含める。
  2. **クライアント側のBLEスキャン**:
     - 他の端末は、この特定のサービスUUIDをスキャンし、アドバタイズパケットを検出する。
  3. **GATT接続と情報交換**:
     - クライアントはホストにGATTで接続し、キャラクタリスティック（Characteristic）を通じて以下の情報を交換する。
       - **Wi-Fi接続情報**: 各端末のローカルIPアドレス（Wi-Fi Directで動的に割り当てられたIPなど）と、シグナリング用のポート番号。
       - **役割情報**: WebRTCのOfferを出す側か、Answerを返す側かの簡単な役割分担。
  4. **高帯域通信へ切り替え**:
     - BLE経由で得たIPアドレスとポートを使い、端末間で直接TCP/UDPソケット接続を確立。
     - このWi-Fi経由の接続をシグナリングチャネルとして利用し、SDP Offer/AnswerやICE Candidateといったサイズの大きいデータを交換する。
  5. **BLE切断**:
     - Wi-FiでのP2P接続が確立し、WebRTCのPeerConnectionが安定したら、電力消費を抑えるためにBLE接続は切断する。
* **シグナリング内容**：SDP offer/answer、ICE candidates、room control messages（mute/unmute、priority）を交換。

## 2.4 ローカルSFUオプション（拡張）

* 小規模で低遅延をさらに確保したい場合、ローカルに **軽量SFU（Pion SFU / Janus）を Raspberry Pi 4 や携帯ルータ上に展開**。これによりメッシュ→SFUに切り替え可能（端末負荷削減、上行帯域削減）。([digitalsamba.com][5])

---

# 3. 実装の詳細（OS別）

## iOS（推奨構成）

* **Discovery/Signaling**: MultipeerConnectivity（MCNearbyServiceBrowser + MCNearbyServiceAdvertiser）。初期SDP/ICEのやり取りをMCSessionのストリーミング機能で行う。([Apple Developer][2])
* **Media**: AVAudioEngine → WebRTC のネイティブ API に接続（マイク取得 → Opusエンコード → RTP送出）。AVAudioSessionカテゴリは `.playAndRecord`、Bluetoothヘッドセットを許可するオプションを適切に設定。
* **Permissions**: マイク、Local Network（iOS 14+：ローカルネットワーク権限）、Bluetooth（必要なら）。
* **Background**: 音声通話を維持するための Background Modes: Audio を設定。

## Android（推奨構成）

* **Discovery/Signaling**: Nearby Connections API（推奨）または Wi-Fi Direct API。Nearbyは Bluetooth/Wi-Fi を抽象化してくれる。([Google for Developers][6])
* **Media**: AudioRecord / AudioTrack でキャプチャと再生 → WebRTC ネイティブライブラリへルーティング。
* **Permissions**: マイク、位置（Wi-Fi Direct/Nearbyで必要になる場合）、Bluetooth（BLEコントロール時）。
* **Background**: Foreground Service を立てて通話を維持。

---

# 4. Bluetooth の役割（明確）

* **音声トンネル**としてのBluetooth（HFP）をアプリ側で直接作るのは不可・推奨されない（OSの制約、互換性問題）。代わりに：

  * BLE は「招待トークン共有」「ボタンイベント（インカムボタン→ミュート/ペアリング）」「デバイスメタデータ同期」に使う。
  * 実際の音声は WebRTC over Wi-Fi（またはWi-Fi Direct）経byで送受信。
    （※既存インカムヘッドセットを使う場合は、ヘッドセットがシステムで接続されたときにアプリの音声が自動的にそのヘッドセットにルーティングされる点に留意）

---

# 5. 低遅延チューニング（実践的アドバイス）

* **Opus設定**：低レイテンシモード（frame size短め、低の遅延プリセット）を利用。
* **Packetization**：小さめの RTP パケット、FEC/再送のトレードオフを適切に設定。
* **ネットワーク**：Wi-Fiチャネル干渉を避ける（5GHz推奨）。Wi-Fi DirectやAd-hocは距離に強い。
* **CPU負荷**：エンコード設定を調整。メッシュだと送信数が増えるので端末負荷が上がる点に注意。
* **目標**：短距離ローカルなら**往復 latency < 100–150 ms**を目指す（現実的な目標）。sonoBus等のアプリがローカルで低遅延配信の実例あり。([sonobus.net][7])

---

# 6. セキュリティ & プライバシー

* **ローカル接続でも暗号化**：WebRTCのDTLS/SRTPを利用（デフォルトで提供）。
* **発見時の承認フロー**：ユーザーが参加を明示承認。自動接続は避ける（走行中誤接続リスク）。
* **ローカルネットワーク権限表示**（iOS）や位置権限（Android）を透明に説明するUI。

---

# 7. エッジケースとフォールバック

* **混在環境（iOS + Android）**：Multipeer と Nearby の両実装を行い、共通のブリッジ（BLEで最初にroom tokenを渡す→その後UDP/mDNSでSDP交換）を実装する。
* **インターネット接続が有る場合**：同一プロトコル（WebRTC）でクラウドSFUに接続して遠隔とブリッジ。クラウドはあくまでオプション。
* **大きな負荷（>4人）**：ローカルSFU導入を推奨。

---

# 8. リスクと課題（洗い出し）

本プロジェクトは技術的に挑戦的ないくつかの要素を含んでおり、以下のようなリスクが想定される。

| リスク分類 | 具体的な課題 | 深刻度 | 提案される対策 |
| :--- | :--- | :--- | :--- |
| **通信の安定性** | **クロスプラットフォーム（iOS↔Android）の発見・接続の不安定さ**：BLEブリッジは、端末やOSバージョンの差異で接続に失敗したり、遅延が大きくなる可能性がある。 | **高** | <li>PoC-3で重点的にテスト。</li><li>接続失敗時のリトライ機構を実装。</li><li>最悪のケースとして、片方のOSがホスト（アクセスポイント役）になるシンプルなWi-Fi接続モードをフォールバックとして用意。</li> |
| | **走行中のネットワーク切断**：Wi-Fi DirectやP2P接続は、距離や障害物、速度によって瞬断する可能性がある。 | **高** | <li>WebRTCのICE再接続（ICE restart）機構を活用。</li><li>切断を検知し、ユーザーに音声で通知する。</li><li>自動再接続ロジックを実装し、シームレスな復帰を目指す。</li> |
| **パフォーマンス** | **バッテリー消費の激しさ**：マイクの常時起動、音声のエンコード/デコード、Wi-Fi/BLE通信を継続すると、特に古い端末でバッテリーが著しく消耗する。 | **高** | <li>発話がない区間は音声データを送らない（VAD: Voice Activity Detection）。</li><li>画面がオフの時はUI描画を停止するなど、省電力モードを実装。</li><li>PoC-2でCPU使用率とバッテリー消費を実機測定し、ボトルネックを特定。</li> |
| **音声品質** | **ノイズ（風切り音、エンジン音）**：バイク走行中のマイクは環境音を強く拾い、そのままでは会話が困難になる。 | **高** | <li>WebRTCに標準搭載されているノイズサプレッション（NS）、エコーキャンセレーション（AEC）を有効化し、積極的にチューニングする。</li><li>より高度なノイズ除去が必要な場合、RNNoiseなどのサードパーティ製ライブラリの導入を検討。</li> |
| **OSの制約** | **バックグラウンド実行の制限**：特にiOSは、バックグラウンドでのVoIP処理（PushKit Voip Push / Background Mode: Audio）のライフサイクル管理が厳格。長時間（数時間）の連続通話でOSにキルされるリスク。 | **中** | <li>iOSのVoIP Push (PushKit) と `AVAudioSession` の適切な設定を徹底的に検証。</li><li>AndroidではForeground Serviceを利用して継続的な実行を担保する。</li><li>両OSで長時間の連続稼働テストを実施。</li> |
| **UI/UX** | **走行中の安全性**：グローブをした手での操作や、画面を見ずに状態を把握することが求められる。 | **中** | <li>物理的なボタン（ヘッドセットのボタン）との連携を検討。</li><li>接続/切断/ミュートなどの状態変化を、明確な音声フィードバックで伝える設計にする。</li> |

---

# 9. 必要なライブラリ候補（実装の早道）

## ネイティブ開発 (Swift/Kotlin)
* **libwebrtc**（Google公式）
  - **メリット**: パフォーマンスが最も高く、最新のWebRTC機能をフルに活用できる。カスタマイズ性が非常に高い。
  - **デメリット**: ビルドプロセスが複雑で、APIが低レベルなため学習コストが高い。導入とメンテナンスに工数がかかる。
  - **推奨度**: **高**. パフォーマンスと低遅延を最優先する本プロジェクトの要件に最も合致する。

## クロスプラットフォーム開発

### React Native
* **react-native-webrtc**
  - **メリット**: JavaScript/TypeScriptで記述でき、開発速度が速い。コミュニティが活発で多くのサンプルが見つかる。
  - **デメリット**: ネイティブ層のブリッジングに起因する若干のパフォーマンスオーバーヘッド。ネイティブAPIの細かなチューニングが難しい場合がある。
  - **推奨度**: **中**. 迅速なPoC開発には向いているが、製品レベルの低遅延性能を追求する際にはネイティブ実装との比較検討が必須。

### Flutter
* **flutter-webrtc**
  - **メリット**: UIとビジネスロジックをDartで統一でき、コードベースがシンプルになる。パフォーマンスはReact Nativeよりネイティブに近いとされることが多い。
  - **デメリット**: ライブラリの成熟度やコミュニティの規模がReact Nativeに比べて小さい可能性がある。特定のハードウェア連携で問題が発生するケースも報告されている。
  - **推奨度**: **中**. Flutterでの開発経験が豊富なチームには良い選択肢だが、ライブラリの安定性やドキュメントを事前に十分に調査する必要がある。

## SFU（サーバーサイド）
* **Pion (Go)** — 軽量SFUを自前で構築する場合の第一候補（Raspberry Piなどで動作）。
* **Janus / mediasoup** — より高機能で成熟したSFUサーバ。ローカルでの利用も可能。

## 結論
本プロジェクトの「低遅延」「ローカルファースト」という要件を最大限に満たすには、**ネイティブ (libwebrtc)** での実装が最も確実性が高い。ただし、開発リソースや期間に応じてクロスプラットフォームの選択肢も検討の価値がある。

---

# 10. ユーザ操作フロー（例）

1. アプリ起動 → 「近くのライダーを検索」 → BLEまたはMultipeer/Nearbyでルームを検出。
2. 招待/承認 → SDP/ICE を交換 → WebRTC接続確立（各PeerとP2P接続）
3. 音声通話開始（ミュート、優先スピーカー、他のUI）。
4. 「Webモード」を選べばローカルSFU/クラウドSFUで外部通話とブリッジ。

---

# 11. UI/UXに関する考慮事項

バイク乗車中の利用が前提となるため、UI/UXは安全性と直感的な操作性を最優先に設計する必要がある。

*   **ハンズフリー操作の徹底**:
    *   走行中の画面操作は厳禁。基本的な操作（ミュート、特定の相手への呼びかけ等）は、ペアリングしたヘッドセットの物理ボタンや音声コマンドに割り当てることを検討する。
    *   アプリは一度通話を開始したら、スマートフォンをポケットやカバンに入れたままでも機能し続ける設計とする。

*   **明確な音声フィードバック**:
    *   視覚的な確認ができないため、システムのあらゆる状態変化を**音声ガイダンス**でユーザーに伝える。
        *   例：「〇〇が参加しました」「接続が切れました」「ミュート中です」
    *   誰が話しているかを直感的に示す機能（例：優先スピーカーの音量をわずかに上げる）も検討の価値あり。

*   **シンプルで大きなUIコンポーネント**:
    *   走行前の設定画面（グループ作成、ペアリング）は、グローブを装着したままでも操作できるよう、ボタンやスライダーを大きく、間隔を十分に空けて配置する。
    *   ダークモードを基本とし、晴天時の太陽光下でも視認しやすいコントラストを確保する。

*   **自動化とインテリジェンス**:
    *   一度ペアリングした相手とは、次回以降アプリを起動するだけで自動的にグループを再接続するオプションを用意する。
    *   走行開始を検知（加速度センサー等）して自動でマイク感度を調整するなど、状況に応じたインテリジェントな機能も将来的な視野に入れる。

*   **接続状態の可視化**:
    *   走行開始前に、各メンバーとの接続品質（電波強度や遅延）を簡易的に確認できるUIを用意し、安心して出発できるようにする。

---

# 12. テスト項目（必須）

* デバイス組み合わせ試験（iOS(iPhone内蔵Wi-Fi) ↔ Android機種 × 複数）
* 同一LANでのレイテンシ測定（往復・片道）、目標: 1人当たりの往復 < 150ms
* メッシュで4人接続時のCPU使用率とネットワーク上行/下行帯域測定
* ヘッドセット接続時の音声ルーティング検証（HFPヘッドセットとの連携）
* オフライン（AP無し、Wi-Fi Direct）での発見・接続シナリオ検証

---

# 13. マイルストーン（詳細化された開発フェーズ）

## Phase 1: PoC-1 — 基本的な1対1音声通話（同一OS）
*期間目安: 2週間*

*   **タスク**:
    1.  iOSおよびAndroidの基本プロジェクトをセットアップする。
    2.  `libwebrtc`ライブラリを各プロジェクトに導入し、ビルド設定を完了させる。
    3.  IPアドレスをハードコードする方式で、2台の端末間のシグナリングを実装する（手動でIPを入力するUIで可）。
    4.  マイクからの音声を取得し、WebRTC経由で相手に送信する機能を実装する。
    5.  受信した音声をスピーカーから再生する機能を実装する。
*   **検証項目**:
    *   ✅ 同一Wi-Fiネットワーク上の同じOSの端末2台で、音声通話が確立できること。
    *   ✅ 双方向で音声が聞こえ、極端な遅延やエコーがないことを確認する（主観評価）。

## Phase 2: PoC-2 — 4人メッシュ接続とパフォーマンス測定（同一OS）
*期間目安: 3–4週間*

*   **タスク**:
    1.  1対1接続のロジックを拡張し、最大4人でのフルメッシュ接続を管理できるようにする（各端末が他の3台と`PeerConnection`を確立）。
    2.  mDNS (iOS: Bonjour, Android: NsdManager) またはUDPブロードキャストを利用した簡易的な端末発見機能を実装する。
    3.  4人でのSDP/ICE交換を管理するシグナリングロジックを実装する。
    4.  接続中の参加者一覧を表示するシンプルなUIを作成する。
*   **検証項目**:
    *   ✅ 4台の端末が互いを検出し、グループ通話に参加できること。
    *   ✅ 全員の声が他の全員に聞こえることを確認する。
    *   ✅ WebRTCのDataChannel等を用いて簡易的なPing/Pongを実装し、**往復遅延が150ms以下**であることを測定する。
    *   ✅ 4人接続時の**CPU使用率**と**バッテリー消費量**を30分間測定し、実用性を評価する。

## Phase 3: PoC-3 — クロスプラットフォーム接続（iOS ↔ Android）
*期間目安: 4週間*

*   **タスク**:
    1.  「2.3 発見とシグナリング」で設計したBLEブリッジを実装する。
        *   iOS: `CoreBluetooth`フレームワークを使用。
        *   Android: `BluetoothLeScanner`および`BluetoothGattServer` APIを使用。
    2.  Wi-Fi接続情報（IPアドレス、ポート）を交換するためのGATTサービスとキャラクタリスティックを定義・実装する。
    3.  BLEでの情報交換後、Wi-Fi P2Pによる直接のシグナリングチャネルに切り替えるロジックを実装する。
    4.  iOSとAndroidの`libwebrtc`実装間で、SDPやICEのフォーマットに差異がないか確認し、必要であれば吸収する。
*   **検証項目**:
    *   ✅ iOS端末とAndroid端末がBLE経由で互いを発見できること。
    *   ✅ Wi-Fi接続情報を交換し、直接のソケット接続を確立できること。
    *   ✅ iOSとAndroid間での1対1通話が成功すること。
    *   ✅ 2台のiOS端末と2台のAndroid端末など、混在環境での4人メッシュ通話が成功すること。

## Phase 4: 拡張フェーズ
*   **タスク（ローカルSFU）**:
    1.  Raspberry Pi 4等に軽量SFU（Pionを推奨）をセットアップする。
    2.  クライアントアプリに、メッシュ接続とSFU接続を選択できるロジックを追加する。
    3.  SFUへの接続・切断、メディアトラックの送受信機能を実装する。
*   **タスク（クラウドブリッジ）**:
    1.  クラウドサーバーにSFU（Janus, Mediasoup等）をデプロイする。
    2.  遠隔ユーザーを招待するためのUIと、クラウドSFUへの接続機能を実装する。
*   **検証項目**:
    *   ✅ ローカルSFU経由での通話が成功し、メッシュ接続時よりも端末のCPU負荷と上り帯域が削減されることを確認する。
    *   ✅ インターネット経由で、遠隔地のユーザーがローカルグループ通話に参加できること。

---

# 参考（抜粋）

* Apple MultipeerConnectivity ドキュメント（発見＋ストリーミング）. ([Apple Developer][2])
* Android Wi-Fi Direct / Nearby Connections API（P2P 概要）. ([Android Developers][3])
* WebRTC アーキテクチャ（P2P vs SFU）・設計考察. ([Stream][1])
* 低遅延ローカル音声配信の実例（SonoBus 等）. ([sonobus.net][7])

---

もしこれでOKなら、次はどちらに進めますか？（選んでください — どちらでもすぐ作ります）

1. **最短プロトタイプ（コード付き）**：iOSとAndroidで「同一Wi-Fi上の4人メッシュ」最小実装（libwebrtc を使ったサンプル）。
2. **クロス発見設計（実コード）**：iOS:Multipeer + Android:Nearby + BLEブリッジ のサンプル実装（シグナリング交換含む）。
3. **ローカルSFUオプション設計**：Raspberry Pi + Pion/Janus のセットアップ手順とクライアント切替ロジック。

どれを最初に出しますか？（選んだら、具体的なコード／シーケンス図／API一覧を作成します）

[1]: https://getstream.io/resources/projects/webrtc/architectures/p2p/?utm_source=chatgpt.com "Peer-To-Peer (P2P)"
[2]: https://developer.apple.com/documentation/multipeerconnectivity?utm_source=chatgpt.com "Multipeer Connectivity | Apple Developer Documentation"
[3]: https://developer.android.com/develop/connectivity/wifi/wifi-direct?utm_source=chatgpt.com "Create P2P connections with Wi-Fi Direct"
[4]: https://www.sciencedirect.com/science/article/pii/S2542660523002184?utm_source=chatgpt.com "Nearby connections strategies: Features, usage, and ..."
[5]: https://www.digitalsamba.com/blog/p2p-sfu-and-mcu-webrtc-architectures-explained?utm_source=chatgpt.com "P2P, SFU and MCU - WebRTC Architectures Explained"
[6]: https://developers.google.com/nearby/connections/overview?utm_source=chatgpt.com "Overview | Nearby Connections"
[7]: https://sonobus.net/?utm_source=chatgpt.com "SonoBus"
[8]: https://www.moontechnolabs.com/blog/webrtc-architecture/?utm_source=chatgpt.com "A Complete Guide to WebRTC Architecture in 2025"
