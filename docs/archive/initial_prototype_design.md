> **【アーカイブ】** この文書は初期検討版です。2026-10-11 の方針見直し（同一LAN前提・Multipeer/Nearby/BLEブリッジ廃止・Flutter採用）により、
> 最新の内容は [requirements_definition.md](../requirements_definition.md) と [architecture.md](../architecture.md) を参照してください。

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
* **Cross-platformブリッジ**:

  * 1. 互いに相手OSの発見方法を実装（iOS→Multipeer、Android→Nearby）で混在環境に対応する。
  * 2. あるいは BLE を利用して「会話ルームのID」と「ローカルIP候補」を共有 → そこから直接 WebRTC SDP/ICE を交換（UDP mDNS または短距離HTTP over Wi-Fi）。
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
  * 実際の音声は WebRTC over Wi-Fi（またはWi-Fi Direct）経由で送受信。
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

# 8. 必要なライブラリ候補（実装の早道）

* **libwebrtc**（ネイティブ iOS/Android） — WebRTCの公式実装（推奨）。([moontechnolabs.com][8])
* **Pion (Go)** — 軽量SFUを自前で構築する場合の選択肢（Raspberry Piなどで動作）。([digitalsamba.com][5])
* **Janus / mediasoup** — ローカルSFUを検討するときの成熟したサーバ。
* （商用SDKはクラウド寄りだが、実装を楽にする：Agora/Twilio。ただしローカル完全オフラインでは自前WebRTCが有利）

---

# 9. ユーザ操作フロー（例）

1. アプリ起動 → 「近くのライダーを検索」 → BLEまたはMultipeer/Nearbyでルームを検出。
2. 招待/承認 → SDP/ICE を交換 → WebRTC接続確立（各PeerとP2P接続）
3. 音声通話開始（ミュート、優先スピーカー、他のUI）。
4. 「Webモード」を選べばローカルSFU/クラウドSFUで外部通話とブリッジ。

---

# 10. テスト項目（必須）

* デバイス組み合わせ試験（iOS(iPhone内蔵Wi-Fi) ↔ Android機種 × 複数）
* 同一LANでのレイテンシ測定（往復・片道）、目標: 1人当たりの往復 < 150ms
* メッシュで4人接続時のCPU使用率とネットワーク上行/下行帯域測定
* ヘッドセット接続時の音声ルーティング検証（HFPヘッドセットとの連携）
* オフライン（AP無し、Wi-Fi Direct）での発見・接続シナリオ検証

---

# 11. マイルストーン（開発フェーズ提案）

1. **PoC-1（2週間）**：同一プラットフォーム同士でのWebRTC P2P音声（1対1）— ローカルのみ、低遅延確認。
2. **PoC-2（3–4週間）**：メッシュで4人接続（同一OS）。発見は簡易UDP/mDNSで実装。レイテンシ測定。
3. **PoC-3（4週間）**：iOS↔Android混在。Multipeer/Nearby/ BLEブリッジ実装でクロス接続。
4. **拡張**：ローカルSFU on Raspberry Pi（必要なら）／クラウドブリッジの実装。

> 補足：上の期間はあくまで目安で、チーム人員や既存の経験で変わります（ここで期間を保証はしません）。

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
