#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kPrismAppMutexName[] = L"PrismPluralityAppMutex";
constexpr const wchar_t kPrismWindowClassName[] = L"PRISM_RUNNER_WIN32_WINDOW";
constexpr int kFocusRetryAttempts = 100;
constexpr int kFocusRetryDelayMs = 50;

bool FocusExistingPrismWindow() {
  HWND existing_window = ::FindWindow(kPrismWindowClassName, nullptr);
  if (existing_window == nullptr) {
    return false;
  }

  if (::IsIconic(existing_window)) {
    ::ShowWindow(existing_window, SW_RESTORE);
  } else {
    ::ShowWindow(existing_window, SW_SHOWNORMAL);
  }
  ::SetForegroundWindow(existing_window);
  return true;
}

void CloseHandleIfPresent(HANDLE handle) {
  if (handle != nullptr) {
    ::CloseHandle(handle);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  ::SetLastError(ERROR_SUCCESS);
  HANDLE app_mutex = ::CreateMutex(nullptr, TRUE, kPrismAppMutexName);
  if (app_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // If Prism later gains protocol or file associations, forward this
    // process's arguments to the existing instance before exiting here.
    for (int i = 0; i < kFocusRetryAttempts; ++i) {
      if (FocusExistingPrismWindow()) {
        break;
      }
      ::Sleep(kFocusRetryDelayMs);
    }
    CloseHandleIfPresent(app_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  HRESULT com_init = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Prism", origin, size)) {
    if (SUCCEEDED(com_init)) {
      ::CoUninitialize();
    }
    CloseHandleIfPresent(app_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (SUCCEEDED(com_init)) {
    ::CoUninitialize();
  }
  CloseHandleIfPresent(app_mutex);
  return EXIT_SUCCESS;
}
