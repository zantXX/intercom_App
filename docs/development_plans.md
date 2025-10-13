# 開発実装計画書

このドキュメントは、「バイク用インカム風リアルタイム音声通話アプリ」のプロトタイプ開発における実装レベルの詳細を定義します。`docs/requirements_definition.md`で定義された要件に基づき、具体的な技術選定、開発プロセス、品質保証、デプロイ戦略を明確にすることを目的とします。

---

## 1. 利用技術スタック

本プロジェクトでは、パフォーマンス、低遅延、およびOSネイティブ機能（特に通信と音声処理）との親和性を最優先するため、クロスプラットフォーム・フレームワークは採用せず、**ネイティブ開発**を基本方針とする。

| カテゴリ | iOS | Android | 選定理由 |
| :--- | :--- | :--- | :--- |
| **言語** | **Swift 5.x** | **Kotlin 1.8+** | 各プラットフォームの公式推奨言語であり、安全性、表現力、パフォーマンスのバランスが取れているため。 |
| **UIフレームワーク** | **SwiftUI** | **Jetpack Compose** | モダンで宣言的なUI開発が可能。開発効率が高く、リアクティブなUI実装に適しているため。OSの旧バージョンサポートが必要な場合は、UIKit / XMLとの併用も検討。 |
| **アーキテクチャ** | **MVVM-C** (Model-View-ViewModel-Coordinator) | **MVVM** (Model-View-ViewModel) with Clean Architecture | 責務分離を徹底し、テスト容易性とメンテナンス性を高めるため。Coordinatorは画面遷移ロジックを分離する目的で導入。 |
| **WebRTCライブラリ** | **GoogleWebRTC (CocoaPods)** | **libwebrtc.aar (Maven)** | Google公式のWebRTC実装であり、最も信頼性とパフォーマンスが高い。低遅延性能を最大限に引き出すために選択。 |
| **近接通信 (Discovery)** | **CoreBluetooth**, **MultipeerConnectivity** | **Nearby Connections API**, **Android Bluetooth LE API** | 要件定義に基づき、クロスプラットフォームのブリッジングと、同一OS間の最適化された通信を両立させるために使用。 |
| **非同期処理** | **Swift Concurrency (async/await)** | **Kotlin Coroutines** | モダンで可読性の高い非同期コードを記述できるため。コールバック地獄を避け、コードの直感性を高める。 |
| **依存関係管理** | **Swift Package Manager (SPM)** | **Gradle / Maven** | 公式にサポートされており、シンプルで信頼性が高いパッケージ管理ツール。 |
| **ロギング** | **OSLog** | **Timber** | 構造化されたログを効率的に記録・フィルタリングするため。デバッグ効率を向上させる。 |

---

## 2. プロジェクト構成（ファイル・ディレクトリ構造）

iOS/Androidともに、Clean Architectureの思想を取り入れた階層化構造を採用し、各コンポーネントの独立性とテスト容易性を確保する。

### iOS プロジェクト構成 (MVVM-C)

```
IncomApp/
├── Application/      # AppDelegete, SceneDelegate, アプリのエントリーポイント
├── Core/             # アプリ全体で共有される低レベルコンポーネント
│   ├── Network/      # WebRTC, BLE通信の抽象化レイヤー
│   ├── Audio/        # マイク入力、音声出力の管理
│   └── Utils/        # 拡張機能、ヘルパーなど
├── Features/         # 機能ごとのモジュール
│   └── GroupCall/
│       ├── View/     # SwiftUI Views
│       ├── ViewModel/ # Viewの状態とロジック
│       ├── Model/     # その機能で利用するデータ構造
│       └── Coordinator/ # 画面遷移の管理
├── Resources/        # Assets, Plist, ローカライズファイル
└── Preview Content/  # SwiftUIプレビュー用のデータ
```

### Android プロジェクト構成 (MVVM)

```
app/
└── src/main/
    ├── java/com/example/incomapp/
    │   ├── di/             # 依存性注入 (Hilt/Koin)
    │   ├── core/           # アプリ全体で共有される低レベルコンポーネント
    │   │   ├── webrtc/     # WebRTC関連の接続管理
    │   │   ├── nearby/     # Nearby APIの管理
    │   │   └── audio/      # AudioRecord/AudioTrackの管理
    │   ├── data/           # データ層 (Repository, DataSource)
    │   │   ├── model/      # データモデル
    │   │   └── repository/ # データソースの抽象化
    │   ├── ui/             # UI層 (Compose)
    │   │   ├── theme/      # UIテーマ
    │   │   └── features/   # 機能ごとのUI
    │   │       └── groupcall/
    │   │           ├── GroupCallScreen.kt
    │   │           └── GroupCallViewModel.kt
    │   └── IncomApplication.kt # Applicationクラス
    └── res/              # XMLリソース
```

---

## 3. コーディング規約

コードの品質と一貫性を保ち、レビューの負担を軽減するために、以下の規約を設ける。

*   **基本スタイルガイド**:
    *   **iOS**: [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) に準拠する。
    *   **Android**: [Kotlin style guide](https://developer.android.com/kotlin/style-guide) に準拠する。

*   **静的解析ツール**:
    *   **iOS**: **SwiftLint** を導入し、リポジトリに `.swiftlint.yml` を配置する。Xcodeのビルドフェーズにスクリプトを組み込み、警告・エラーをリアルタイムに検出する。
    *   **Android**: **Ktlint** を導入し、Gradleタスクとして設定する。`ktlintCheck` をCIで実行し、規約違反を検出する。

*   **強制アンラップの禁止**:
    *   `!` を用いたImplicitly Unwrapped Optionalや強制アンラップは原則禁止。`guard let` や `if let` を用いて安全にアンラップする。

*   **命名規則**:
    *   クラス名、メソッド名、変数名は、その役割が明確にわかるように具体的かつ冗長に命名する（例: `fetchAndCacheUserProfile`）。
    *   Boolean値の変数は `is~`, `has~`, `can~` などの接頭辞で始める。

*   **コメント**:
    *   複雑なロジックや、なぜその実装にしたのかという「意図」を説明するコメントを記述する。何をしているか自明なコードにコメントは不要。
    *   `// MARK: -` を活用し、クラス内の実装を論理的なブロックに分割する。

---

## 4. テスト計画

品質を保証し、リグレッションを早期に検出するために、以下の多層的なテスト戦略を採用する。

| テストレベル | 目的 | iOS | Android | 実施タイミング |
| :--- | :--- | :--- | :--- | :--- |
| **ユニットテスト (Unit Test)** | 個々のクラスやメソッドが仕様通りに動作することを確認する。ビジネスロジックやViewModelのテストが中心。 | **XCTest** | **JUnit5**, **Mockito/MockK** | Pull Request作成時 (CI) |
| **結合テスト (Integration Test)** | 複数のコンポーネント（例: ViewModelとRepository）を連携させ、正しく動作することを確認する。 | **XCTest** | **AndroidJUnit4** | Pull Request作成時 (CI) |
| **UIテスト (UI Test)** | ユーザー操作をシミュレートし、画面遷移や表示が期待通りであることを確認する。 | **XCTest (UI Testing)** | **Espresso**, **Compose Test** | Nightly Build (CI) |
| **E2Eテスト (End-to-End Test)** | **複数端末**を実際に連携させ、発見・接続・通話という一連のシナリオが正常に完了することを確認する。 | (手動) | (手動) | 各PoC完了時 |
| **パフォーマンステスト** | CPU使用率、バッテリー消費、ネットワーク帯域、音声遅延などを測定し、要件を満たしているかを確認する。 | **Instruments**, **MetricKit** | **Android Profiler**, **Perfetto** | PoC-2完了時、リリース前 |

*   **カバレッジ目標**: ユニットテストのカバレッジは、重要なビジネスロジックにおいて**80%以上**を目指す。
*   **E2Eテストの自動化**: 将来的には、複数台のシミュレータ/エミュレータを連携させるテストフレームワーク（例: Maestro）の導入を検討する。

---

## 5. デプロイ計画

手動でのビルド・デプロイ作業をなくし、迅速かつ一貫性のあるリリースを実現するため、**GitHub Actions** を用いたCI/CDパイプラインを構築する。

### CI (Continuous Integration)

*   **トリガー**: `main`ブランチまたは`develop`ブランチへのPull Request作成・更新時。
*   **実行ジョブ**:
    1.  **Lint & Static Analysis**: SwiftLint / Ktlint を実行し、コーディング規約をチェック。
    2.  **Build**: アプリが正常にビルドできることを確認。
    3.  **Unit & Integration Tests**: ユニットテストおよび結合テストを実行。
*   **成功条件**: すべてのジョブが成功した場合のみ、Pull Requestのマージを許可する。

### CD (Continuous Deployment)

*   **`develop` ブランチへのマージ時**:
    *   **トリガー**: `develop`ブランチに直接pushまたはPull Requestがマージされた時。
    *   **デプロイ先**:
        *   **iOS**: TestFlightの内部テストグループに**自動配信**。
        *   **Android**: Google Play Consoleの**内部テストトラック**に**自動配信**。
    *   **バージョン管理**: ビルド番号を自動でインクリメントする。

*   **`main` ブランチへのマージ時 (リリース)**:
    *   **トリガー**: `main`ブランチにGitタグ（例: `v1.0.0`）がpushされた時。
    *   **デプロイ先**:
        *   **iOS**: App Store Connectへのアップロードと、バージョン提出（手動承認）。
        *   **Android**: Google Play Consoleの**製品版トラック**へのリリース（段階的リリースを推奨）。
    *   **自動化**: リリースノートの自動生成（Conventional Commits規約を推奨）。

---

## 6. その他

### バージョン管理

*   **バージョン番号**: `Major.Minor.Patch` の[セマンティックバージョニング](https://semver.org/lang/ja/)に準拠する。
    *   **Major**: 後方互換性のない大きな変更。
    *   **Minor**: 後方互換性のある機能追加。
    *   **Patch**: 後方互換性のあるバグ修正。
*   **ビルド番号**: CI/CDでビルドごとに自動インクリメントする整数値。

### ブランチ戦略

*   **[GitHub Flow](https://docs.github.com/ja/get-started/quickstart/github-flow) をベースとしたシンプルな戦略**を採用する。
    *   `main`: 常にリリース可能な安定ブランチ。直接のpushは禁止。
    *   **Featureブランチ**: `main`から切り、`feat/`プレフィックスを付ける（例: `feat/group-call-ui`）。作業完了後、`main`へのPull Requestを作成する。
    *   **Hotfixブランチ**: `main`から切り、`fix/`プレフィックスを付ける。緊急のバグ修正にのみ使用。

### コードレビュープロセス

*   `main`ブランチへのマージは、Pull Request (PR) を経由して行うことを必須とする。
*   PRは、**最低1人以上**のレビュワーから `Approve` を得る必要がある。
*   CIのすべてのチェックがパスしていることを必須条件とする。
*   レビュワーは、ロジックの妥当性、設計の適切性、規約の遵守、テストコードの網羅性を中心に確認する。
*   PRのテンプレートを用意し、変更の概要、目的、テスト内容を記述することを義務付ける。
