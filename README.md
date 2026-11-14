<p align="center">
  <img src="assets/app_icon.png" width="128" height="128" alt="PDFREOR Icon" style="border-radius: 28px;" />
</p>

<h1 align="center">PDFREOR</h1>

<p align="center">
  <b>An AI-built, fast, stylus-ready PDF reader and annotation editor for Android tablets.</b><br />
  <sub>Version 3.0.0 · Crafted with AI</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Built%20with-AI-8E24AA?style=flat-square" alt="Built with AI" />
  <img src="https://img.shields.io/badge/Version-3.0.0-1E88E5?style=flat-square" alt="Version 3.0.0" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20Tablet-blue?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-%5E3.12.2-0175C2?style=flat-square&logo=dart" alt="Dart" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License" />
</p>

<p align="center">
  <a href="#english">English</a> ·
  <a href="#日本語">日本語</a> ·
  <a href="#简体中文">简体中文</a>
</p>

---

<a id="english"></a>

## 📖 English

### Overview

**PDFREOR** (`v3.0.0`) is an **AI-crafted** PDF reader and annotation editor tailored for Android tablets, built with Flutter, `pdfrx`, and `syncfusion_flutter_pdf`. From its dual-input stylus canvas and compact LaTeX rasterizer to its zero-bloat **Advanced** editable persistence engine and test suite, the application was designed, implemented, and refined through AI-assisted software engineering.

### Key Features

#### 🖊️ Stylus & Dual-Input Annotation
- **Automatic Stylus Detection & Palm Rejection**: Automatically switches to stylus-only drawing when an active stylus is detected (`PointerDeviceKind.stylus` / `invertedStylus`), letting fingers pan, zoom, tap links, and move or resize objects naturally.
- **Hardware Button Eraser**: Supports native Android stylus barrel button eraser toggling (`com.yin.pdfreor/stylus`) alongside secondary pointer button erasing and whole-stroke hit erasing.
- **Compact Vector Export**: Simplifies polylines with Ramer-Douglas-Peucker (RDP) and quantizes PDF coordinates to 0.1 pt for crisp rendering and smaller output files.

#### 📐 Shapes, Text Boxes, LaTeX & Clipboard Paste
- **Vector Shapes**: Draw Rectangles, Rounded Rectangles, Circles, Straight Lines, and Arrows—either via the floating toolbar or as one-shot finger-drag shapes from the long-press canvas menu.
- **Text Boxes**: Drag, resize width, switch font family (`Sans Serif`, `Serif`, `Monospace`) and font size, with 120% display box height headroom.
- **LaTeX Math Boxes**: Real-time formula preview while editing (`flutter_math_fork`), customizable quick-insert LaTeX operator strip in Settings, 120% display height for tall operators (`\sum`, `\int`, `\prod`, etc.), and ~200 DPI compact PNG export with formula deduplication.
- **Text Selection Markup**: Highlight, Underline, and Strikethrough directly on selectable PDF text (with automatic merging of collinear rects).
- **Clipboard Image & Text Paste**: Paste copied text or clipboard images directly onto a page via the long-press context menu.

#### 💾 Advanced & Standard Annotation Persistence (v3.0.0)
- **Advanced (Editable) Format**: Writes cleanly tagged annotation content streams (`PdfreorAnnV1` / `PdfreorAnnRes`) plus a gzip-compressed annotation payload (`pdfreor_annotations_v1.json.gz`), allowing full re-editing after reopening while stripping old annotation layers on re-save to prevent file growth.
- **Standard (Flattened) Format**: Permanently bakes all annotations into standard PDF content compatible with any third-party viewer.
- **Flexible Settings & Save Menu**: Choose the default open/save behavior in Settings (`File Default`, `Always Advanced`, or `Always Standard`), tap **Save** to save immediately, or **long-press Save** to open **Save Options** (`Save — Advanced`, `Save — Standard`, `Export Standard Copy`).

#### 📑 Multi-Tab Reader & Page Management
- **Multi-Tab Capsule Bar**: Open multiple PDFs simultaneously with unsaved change indicators (`•`) and automatic restoration of last visited page and zoom level.
- **Page Manager**: Stage page deletions and append blank pages, then apply atomically when saving.
- **Fast Navigation**: Page index jump dialog, fast scrollbar, edge-tap page turning, and integrated PDF link navigation.

#### 📁 Document Library & File Operations
- **Background Storage Scanner**: Scans device storage and custom directories in background Dart isolates, plus manual PDF import.
- **File Management**: Search, sort (by Date, Name, Size), switch between List and Grid views, group by folder, batch select, Copy/Cut/Paste across folders, Rename, Share, and Open with external apps.

### Tech Stack

| Layer | Technology |
| --- | --- |
| Development Workflow | AI-assisted architecture, implementation, optimization, and automated test verification |
| Framework | Flutter & Dart (`^3.12.2`), Material 3 (Light & Dark, edge-to-edge) |
| PDF Viewing & Thumbnails | [`pdfrx`](https://pub.dev/packages/pdfrx) (`^2.4.8`) |
| PDF Writing & Structure Editing | [`syncfusion_flutter_pdf`](https://pub.dev/packages/syncfusion_flutter_pdf) (`^35.1.42`) |
| LaTeX Rendering | [`flutter_math_fork`](https://pub.dev/packages/flutter_math_fork) (`^0.7.4`) |
| Android Native Channel | Kotlin (`com.yin.pdfreor/stylus`) for stylus state, button events, clipboard images, and URL launch |
| Utilities | `file_picker`, `permission_handler`, `path_provider`, `open_filex`, `share_plus`, `intl`, `crypto`, `path` |

### Getting Started

#### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) compatible with Dart `^3.12.2`
- Android SDK (`compileSdk = 37`, Java 17)

#### Setup, Test, and Build
```bash
# Clone the repository
git clone https://github.com/yingongsui/PDFREOR.git
cd PDFREOR

# Install dependencies
flutter pub get

# Run static analysis and unit/widget tests
flutter analyze
flutter test

# Run on a connected Android device/tablet
flutter run

# Build APK
flutter build apk --debug
flutter build apk --release
```

---

<a id="日本語"></a>

## 📖 日本語

### 概要

**PDFREOR**（`v3.0.0`）は、**AI を活用して設計・実装・最適化された** Android タブレット向け PDF リーダー兼スタイラス注釈エディターです。Flutter、`pdfrx`、`syncfusion_flutter_pdf` を基盤とし、マルチタブ閲覧、パームリジェクション対応の手書き入力、図形・テキストボックス・LaTeX 数式ボックス、ページ編集、さらに再編集可能な **Advanced** 保存と標準 PDF として統合する **Standard** 保存まで、一連のアーキテクチャと検証テストを含めて AI 支援開発により構築されています。

### 主な機能

#### 🖊️ スタイラス手書き・デュアル入力
- **スタイラス自動検出 & パームリジェクション**：アクティブスタイラス（`stylus` / `invertedStylus`）を検出すると自動的にペン専用描画モードへ切り替わり、指操作でのスクロール、ピンチズーム、リンクタップ、要素の移動・リサイズを妨げません。
- **スタイラスボタン消しゴム対応**：Android ネイティブチャネル（`com.yin.pdfreor/stylus`）経由でスタイラスのボタンによる消しゴム切り替えに対応し、ストローク単位で素早く消去できます。
- **最適化されたベクター出力**：Ramer-Douglas-Peucker（RDP）簡略化と `0.1 pt` 単位の座標量子化により、滑らかな描線とコンパクトなファイルサイズを両立します。

#### 📐 図形・テキストボックス・LaTeX 数式・クリップボード貼り付け
- **5 種類のベクター図形**：長方形、角丸長方形、円、直線、矢印に対応。ツールバーからの連続描画に加え、キャンバス長押しメニューから指ドラッグによる単発描画も可能です。
- **テキストボックス**：自由移動・幅リサイズ・フォント（Sans Serif / Serif / Monospace）・文字サイズ変更に対応。編集完了後の表示枠は上下に `120%` の余白を確保して見やすく表示されます。
- **LaTeX 数式ボックス**：編集中のリアルタイムプレビュー（`flutter_math_fork`）や設定画面でのクイック記号バーのカスタマイズに対応。編集確定後の枠体高さを `120%` に拡張しており、`\sum` や `\int` などの大型演算子も見切れにくく表示されます。PDF 書き出し時は約 `200 DPI` の高効率 PNG として埋め込み、同一数式は自動で重複排除されます。
- **テキスト選択マークアップ**：PDF 上のテキストに対してハイライト、下線、取り消し線を追加でき、書き出し時には同一行の隣接矩形を結合します。
- **クリップボード貼り付け**：キャンバス長押しメニューから、テキストや画像（Android ネイティブの画像クリップボード取得に対応）をページ上に直接貼り付けられます。

#### 💾 Advanced / Standard 注釈保存方式（v3.0.0）
- **Advanced（再編集可能フォーマット）**：独立タグ付きコンテンツストリーム（`PdfreorAnnV1` / `PdfreorAnnRes`）と Gzip 圧縮 JSON ペイロード（`pdfreor_annotations_v1.json.gz`）を埋め込みます。再度開いた際に手書きや図形・テキストをそのまま編集でき、再保存時は旧注釈ストリーム・リソースを適切に除去するためファイルサイズの肥大化を防ぎます。
- **Standard（フラット化フォーマット）**：すべての注釈を標準の PDF コンテンツとして焼き込み、一般的な PDF ビューアで確実に表示できます。
- **設定と保存オプションメニュー**：
  - 設定画面で起動・保存の既定動作（`File Default` / `Always Advanced` / `Always Standard`）を選択できます。
  - フローティングツールバーの **Save** をタップすると現在のモードで保存し、**長押し**すると保存オプションダイアログ（`Save — Advanced` / `Save — Standard` / `Export Standard Copy`）が開きます。

#### 📑 マルチタブ閲覧・ページ管理
- **マルチタブバー**：複数ドキュメントを同時に開き、未保存インジケーター（`•`）表示や前回のページ位置・ズーム倍率の自動復元を行います。
- **ページ管理ダイアログ**：ページの削除予定および末尾への白紙ページ追加を一括管理し、保存時に注釈のページ番号も整合性を保ったまま反映します。
- **快適なナビゲーション**：高速スクロールバー、画面端タップでのページ送り、ページ番号ジャンプ、PDF 内外リンク遷移に対応しています。

#### 📁 ドキュメントライブラリ管理
- **バックグラウンドストレージスキャン**：Dart Isolate による端末ストレージ／任意フォルダのスキャンと、手動での PDF インポートに対応。
- **ライブラリ操作**：検索、並び替え（更新日時・名前・サイズ）、リスト／グリッド表示切替、フォルダ別グループ表示、複数選択、フォルダ間のコピー／切り取り／貼り付け、リネーム、共有、外部アプリでの起動が可能です。

### 技術スタック

| レイヤー | 採用技術 |
| --- | --- |
| 開発スタイル | AI 主導の設計・実装・コード最適化および自動テスト検証 |
| フレームワーク | Flutter / Dart（`^3.12.2`）、Material 3（ライト／ダーク対応、Edge-to-Edge） |
| PDF 表示・サムネイル | [`pdfrx`](https://pub.dev/packages/pdfrx)（`^2.4.8`） |
| PDF 生成・構造編集 | [`syncfusion_flutter_pdf`](https://pub.dev/packages/syncfusion_flutter_pdf)（`^35.1.42`） |
| LaTeX 数式描画 | [`flutter_math_fork`](https://pub.dev/packages/flutter_math_fork)（`^0.7.4`） |
| Android ネイティブ連携 | Kotlin（`com.yin.pdfreor/stylus`）：スタイラス検知・ボタンイベント・画像クリップボード・URL 起動 |
| 周辺ライブラリ | `file_picker`、`permission_handler`、`path_provider`、`open_filex`、`share_plus`、`intl`、`crypto`、`path` |

### ビルド・実行手順

```bash
# リポジトリをクローン
git clone https://github.com/yingongsui/PDFREOR.git
cd PDFREOR

# 依存パッケージを取得
flutter pub get

# 静的解析とテストを実行
flutter analyze
flutter test

# 接続した Android 端末で実行
flutter run

# APK をビルド
flutter build apk --debug
flutter build apk --release
```

---

<a id="简体中文"></a>

## 📖 简体中文

### 项目简介

**PDFREOR**（`v3.0.0`）是一款**完全基于 AI 辅助设计与构建**的 Android 平板 PDF 阅读器与手写批注编辑器，采用 Flutter、`pdfrx` 与 `syncfusion_flutter_pdf` 开发。从多标签流畅阅读、主动笔双输入防误触、LaTeX 公式光栅化与去重、零膨胀 **Advanced** 可编辑持久化引擎，到代码结构优化与单元测试验证，整体工程均由 AI 协作完成。

### 核心功能

#### 🖊️ 手写笔与双输入防误触
- **主动笔自动识别与防误触**：检测到主动电容笔（`stylus` / `invertedStylus`）后自动启用仅触控笔书写模式，手指可自然进行滑动翻页、双指缩放、点击链接及拖动/调整元素大小。
- **笔身按键橡皮擦**：通过 Android 原生通道（`com.yin.pdfreor/stylus`）支持手写笔侧键切换橡皮擦，并支持整条笔画快速擦除。
- **高效矢量路径导出**：导出时使用 Ramer-Douglas-Peucker（RDP）算法简化笔迹并将坐标量化至 `0.1 pt`，兼顾清晰度与文件体积。

#### 📐 图形、文本框、LaTeX 公式与剪贴板粘贴
- **5 种矢量图形**：矩形、圆角矩形、圆形、直线、箭头，支持工具栏常驻绘制或长按画布触发单次手指拖拽绘制。
- **浮动文本框**：支持自由拖拽位置、右侧手柄调整宽度、修改字体（无衬线 / 衬线 / 等宽）与字号；编辑完成后的展示框体高度扩展至 `120%`，视觉留白更充裕。
- **LaTeX 数学公式框**：编辑时内置实时预览（`flutter_math_fork`），支持在设置中自定义快捷算符栏顺序与内容；完成编辑后框体高度扩展至 `120%` 以完整显示 `\sum`、`\int` 等大型算符，并在导出 PDF 时按约 `200 DPI` 光栅化且自动复用相同公式资源。
- **PDF 文本选区标注**：支持对可选文本添加高亮、下划线和删除线，导出时自动合并同行相邻矩形。
- **剪贴板粘贴**：长按画布菜单支持直接粘贴剪贴板中的文本或图片（含 Android 原生图片剪贴板读取）。

#### 💾 Advanced 与 Standard 批注持久化（v3.0.0）
- **Advanced（高级可编辑格式）**：在标准可见图层之外嵌入独立标记的内容流（`PdfreorAnnV1` / `PdfreorAnnRes`）与 Gzip 压缩的 JSON 批注附件（`pdfreor_annotations_v1.json.gz`）。重新打开后可继续移动、修改或删除历史批注，且重复编辑保存时会自动清理旧批注流与资源，避免文件体积持续膨胀。
- **Standard（标准扁平化格式）**：将所有批注永久写入普通 PDF 图层，兼容任意第三方 PDF 阅读器。
- **设置项与长按保存菜单**：
  - 设置页提供三种默认持久化策略：**文件默认（File Default）**、**始终使用 Advanced（Always Advanced）**、**始终使用 Standard（Always Standard）**。
  - 阅读页浮动工具栏中，**轻触 Save** 按当前模式直接保存；**长按 Save** 弹出保存选项框，可随时选择 `Save — Advanced`、`Save — Standard` 或 `Export Standard Copy`（另存为独立扁平化副本而不改动原文件）。

#### 📑 多标签阅读与页面管理
- **胶囊多标签栏**：支持同时打开多个文档，显示未保存状态标识（`•`），并自动记忆每个文档上次阅读的页码与缩放比例。
- **页面管理弹窗**：支持暂存删除指定页面及末尾新增空白页，保存时原子写入并自动重映射批注所在页码。
- **便捷浏览控制**：支持系统字体发现、目录/页码快速跳转、快速滚动条、边缘轻触翻页及 PDF 内部/外部链接跳转。

#### 📁 文档库与文件管理
- **后台多线程扫描**：在后台 Dart Isolate 中扫描设备存储或用户指定目录，也支持手动导入 PDF 文件。
- **库管理操作**：支持关键词搜索、按日期/名称/大小排序、列表与网格视图切换、文件夹分组、多选批量操作、跨目录复制/剪切/粘贴、重命名、系统分享及外部应用打开。

### 技术栈

| 模块 | 实现方案 |
| --- | --- |
| 开发方式 | 基于 AI 的全流程架构设计、实现、代码精简优化与测试验证 |
| 应用框架 | Flutter / Dart（`^3.12.2`），Material 3（自适应浅色/深色主题与全面屏显示） |
| PDF 渲染与缩略图 | [`pdfrx`](https://pub.dev/packages/pdfrx)（`^2.4.8`） |
| PDF 导出与底层编辑 | [`syncfusion_flutter_pdf`](https://pub.dev/packages/syncfusion_flutter_pdf)（`^35.1.42`） |
| LaTeX 公式渲染 | [`flutter_math_fork`](https://pub.dev/packages/flutter_math_fork)（`^0.7.4`） |
| Android 原生能力 | Kotlin（`com.yin.pdfreor/stylus`）：手写笔连接/按键事件、剪贴板图片、URL 打开 |
| 文件与工具依赖 | `file_picker`、`permission_handler`、`path_provider`、`open_filex`、`share_plus`、`intl`、`crypto`、`path` |

### 快速开始

```bash
# 克隆仓库
git clone https://github.com/yingongsui/PDFREOR.git
cd PDFREOR

# 获取依赖
flutter pub get

# 运行静态检查与测试
flutter analyze
flutter test

# 在已连接的 Android 设备上运行
flutter run

# 构建 APK
flutter build apk --debug
flutter build apk --release
```

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
