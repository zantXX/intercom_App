# 配布用APK（Releases）

| ファイル名 | 対象端末 | 内容 |
|---|---|---|
| `intercom-app-release.apk` | Android 8.0以上（64bit ARM / `arm64-v8a`） | リリースビルド版（Google Pixel 8a / OPPO Reno3 A ほか現行のほぼ全Android端末に対応） |

## インストール方法（スマホ単体）
1. `intercom-app-release.apk` をスマホにダウンロード（またはLINE / Discord / Googleドライブ等で共有）します。
2. ファイルを開き、初回のみ「この提供元の不明なアプリを許可」をONにしてインストールします。

## 更新ビルド方法（開発者向け）
```powershell
cd app
flutter build apk --release --split-per-abi
Copy-Item build\app\outputs\flutter-apk\app-arm64-v8a-release.apk ..\releases\intercom-app-release.apk -Force
```
