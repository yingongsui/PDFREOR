#include <cstdio>
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <io.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Direct GUI launches without a parent console leave stdin/stdout/stderr without
// valid Win32 handles, causing Dart isolate writes to stderr (e.g., from PDF
// font registration) to throw StdoutException. Bind missing handles to NUL
// without creating a visible console window.
void EnsureStandardHandlesIfMissing() {
  FILE* dummy = nullptr;
  if (_fileno(stdin) < 0 ||
      ::GetStdHandle(STD_INPUT_HANDLE) == nullptr ||
      ::GetStdHandle(STD_INPUT_HANDLE) == INVALID_HANDLE_VALUE) {
    ::freopen_s(&dummy, "NUL", "r", stdin);
  }
  if (_fileno(stdout) < 0 ||
      ::GetStdHandle(STD_OUTPUT_HANDLE) == nullptr ||
      ::GetStdHandle(STD_OUTPUT_HANDLE) == INVALID_HANDLE_VALUE) {
    ::freopen_s(&dummy, "NUL", "w", stdout);
  }
  if (_fileno(stderr) < 0 ||
      ::GetStdHandle(STD_ERROR_HANDLE) == nullptr ||
      ::GetStdHandle(STD_ERROR_HANDLE) == INVALID_HANDLE_VALUE) {
    ::freopen_s(&dummy, "NUL", "w", stderr);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  EnsureStandardHandlesIfMissing();

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"PDFREOR", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
