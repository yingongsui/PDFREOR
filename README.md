<p align="center">
  <img src="assets/app_icon.png" width="128" height="128" alt="PDFREOR Icon" style="border-radius: 28px;" />
</p>

<h1 align="center">PDFREOR</h1>

<p align="center">
  <b>A modern, high-performance PDF reader and stylus annotation tool tailored for Android tablets.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20Tablet-blue?style=flat-square" alt="Platform" />
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?style=flat-square&logo=dart" alt="Dart" />
</p>

---

## 📖 Overview

**PDFREOR** is an Android tablet-focused PDF application designed for smooth reading, fast document switching, and intuitive stylus note-taking. Built with Flutter and native graphics acceleration, it provides a distraction-free environment for reading academic papers, annotating documents, and managing multi-file workflows.

---

## ✨ Features

### 🖊️ Stylus & Handwriting Annotation
- **Smooth Stroke Smoothing**: Real-time Catmull-Rom spline curve interpolation for natural, fluid handwriting.
- **Multiple Tool Modes**:
  - **Pen**: Precision ballpoint pen simulation.
  - **Highlighter**: Translucent color overlay that keeps underlying PDF text legible.
  - **Eraser**: Fast stroke and point erasing.
- **Customizable Palettes**: Adjustable stroke width, opacity, and curated color palettes.
- **Palm Rejection Support**: Optimized input handling for active stylus pens (e.g., Lenovo Legion Stylus, S-Pen).

### 💬 Floating Text Box Annotations
- **Movable & Resizable**: Freely place, drag, and resize text boxes on any document page.
- **Floating Style Toolbar**: Instantly adjust font size, change text colors, or delete annotations directly above the selected text box.
- **Clean PDF Export**: Annotations are cleanly rasterized and merged without bloating the resulting PDF file size.

### 📑 Navigation & Multi-Document Tabs
- **Capsule Multi-Tab Bar**: Rounded capsule tabs in the top navigation bar for one-tap switching and closing of opened documents.
- **Thumbnail Drawer**: Page index capsule that expands into a right-side thumbnail preview drawer for fast visual page jumping.

### 📁 Document Library & Management
- **Automatic Scanner**: Quickly detects PDF files stored across device storage.
- **Context Menu Actions**: Directly copy, cut, paste, delete, and duplicate PDF files from the library interface.
- **Floating Action Window**: Compact floating control hub for rapid saving, undo/redo, and tool swapping.

### 🎨 Material You & Modern UI
- **Dark Neon Aesthetics**: Deep space gradient background (`#0b111e` to `#030712`) with glowing neon accents.
- **Android Adaptive & Themed Icons**: Fully compliant with Android 13+ adaptive icon standards, including transparent monochrome support for Material You dynamic system color theming.

---

## 🛠️ Tech Stack

- **Framework**: [Flutter](https://flutter.dev) (Dart)
- **PDF Viewing & Manipulation**:
  - [`syncfusion_flutter_pdf`](https://pub.dev/packages/syncfusion_flutter_pdf)
  - [`syncfusion_flutter_pdfviewer`](https://pub.dev/packages/syncfusion_flutter_pdfviewer)
- **Page Rasterization**: [`pdfx`](https://pub.dev/packages/pdfx)
- **File System & Permissions**: [`path_provider`](https://pub.dev/packages/path_provider), [`file_picker`](https://pub.dev/packages/file_picker), [`permission_handler`](https://pub.dev/packages/permission_handler)

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`^3.12.0` or higher)
- [Android SDK](https://developer.android.com/studio) with Android API 34+ platform tools

### Clone and Run

```bash
# Clone the repository
git clone https://github.com/yingongsui/PDFREOR.git
cd PDFREOR

# Fetch dependencies
flutter pub get

# Run on connected Android tablet
flutter run -d <device-id>
```

### Build APK

```bash
# Build Debug APK
flutter build apk --debug

# Build Release APK
flutter build apk --release
```

---

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
