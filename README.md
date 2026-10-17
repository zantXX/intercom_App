# インターコムアプリ（開発中）

スマホだけで動く、バイク用インカム風のグループ音声通話アプリ。
同じネットワーク（テザリング / Wi-Fi）にいる最大4人と、インターネット無しで常時通話できる。

## ドキュメント

| 文書 | 内容 |
|---|---|
| [要件定義書](docs/requirements_definition.md) | 目的・想定シーン・機能/非機能要件（MVP） |
| [方式設計書](docs/architecture.md) | 構成・画面・シグナリング・音声・バックグラウンド・マイルストーン |
| [配布用APK](releases/README.md) | 実機インストール・配布用のリリースAPK（`releases/intercom-app-release.apk`） |
| [初期検討版（アーカイブ）](docs/archive/initial_prototype_design.md) | 方針見直し前の設計 |

## 現在のステータス

- 対象：Android（Flutter）
- 検証端末：Google Pixel 8a, OPPO Reno3 A
- フェーズ：**M1 達成（1対1通話確認）** → **M2（自動検出・最近の接続・自動参加）＋ M4（音声出力切替）＋ ノイズゲート・録音テスト 実装完了**
