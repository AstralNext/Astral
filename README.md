# Astral

Flutter 客户端（Windows / Linux / Android）。

## 构建

```bash
flutter pub get
flutter run -d windows
```

Windows 安装包（需先 `flutter build windows --release`）：

```bash
# 需安装 Inno Setup 6
ISCC installer/astral.iss /DMyAppVersion=1.0.0
```

CI：见 `.github/workflows/build.yml`。

## Android 签名

复制 `android/key.properties.example` → `android/key.properties`，配置本机 keystore（勿提交密钥）。
