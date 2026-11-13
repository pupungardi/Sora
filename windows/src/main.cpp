// Sora — Windows shell.
//
// Windows video output is libmpv (loaded at runtime from mpv-2.dll). Magnet
// resolution goes through the nuvio-engine C API, which serves the selected
// file over loopback HTTP; mpv then opens that URL like any other stream.
//
// Sora ships no catalogue and no addons. The only input is a magnet or a URL
// the user already owns or is licensed to watch.

#ifndef WINVER
#define WINVER 0x0A00
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <initializer_list>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

#include "mpv_dynamic.h"

#ifdef SORA_HAS_NUVIO_ENGINE
#include <nuvio_engine/nuvio_engine.h>
#endif

namespace {

constexpr int kIdInput = 1001;
constexpr int kIdPlay = 1002;
constexpr int kIdStatus = 1003;
constexpr int kIdVideo = 1004;

constexpr int kRowHeight = 44;
constexpr int kStatusHeight = 24;

HWND g_window = nullptr;
HWND g_input = nullptr;
HWND g_play = nullptr;
HWND g_status = nullptr;
HWND g_video = nullptr;

mpv::api g_mpv;
mpv::handle* g_mpv_handle = nullptr;

#ifdef SORA_HAS_NUVIO_ENGINE
nuvio_engine* g_engine = nullptr;
#endif

// ---------------------------------------------------------------- utilities

std::string toUtf8(std::wstring_view text) {
    if (text.empty()) {
        return {};
    }
    const int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                                         nullptr, 0, nullptr, nullptr);
    std::string out(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size,
                        nullptr, nullptr);
    return out;
}

std::wstring fromUtf8(std::string_view text) {
    if (text.empty()) {
        return {};
    }
    const int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                                         nullptr, 0);
    std::wstring out(static_cast<size_t>(size), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
    return out;
}

std::wstring inputText() {
    const int length = GetWindowTextLengthW(g_input);
    std::wstring buffer(static_cast<size_t>(length) + 1, L'\0');
    GetWindowTextW(g_input, buffer.data(), length + 1);
    buffer.resize(static_cast<size_t>(length));
    return buffer;
}

void setStatus(const std::wstring& text) {
    SetWindowTextW(g_status, text.c_str());
}

void setBusy(bool busy) {
    EnableWindow(g_play, busy ? FALSE : TRUE);
}

bool startsWithIgnoreCase(const std::string& value, std::string_view prefix) {
    if (value.size() < prefix.size()) {
        return false;
    }
    for (size_t i = 0; i < prefix.size(); ++i) {
        const auto left = static_cast<unsigned char>(value[i]);
        const auto right = static_cast<unsigned char>(prefix[i]);
        if (std::tolower(left) != std::tolower(right)) {
            return false;
        }
    }
    return true;
}

std::wstring engineDirectory() {
    wchar_t buffer[MAX_PATH * 2]{};
    const DWORD length =
        GetEnvironmentVariableW(L"LOCALAPPDATA", buffer, static_cast<DWORD>(std::size(buffer)));
    if (length == 0 || length >= std::size(buffer)) {
        return L".\\sora-engine";
    }
    std::wstring path(buffer, length);
    path += L"\\Sora\\engine";
    return path;
}

void ensureDirectory(const std::wstring& path) {
    // Good enough for %LOCALAPPDATA%\Sora\engine: create the two parents too.
    const size_t first = path.find(L'\\');
    size_t position = path.find(L'\\', first + 1);
    while (position != std::wstring::npos) {
        CreateDirectoryW(path.substr(0, position).c_str(), nullptr);
        position = path.find(L'\\', position + 1);
    }
    CreateDirectoryW(path.c_str(), nullptr);
}

// -------------------------------------------------------------------- libmpv

bool startMpv() {
    if (g_mpv_handle != nullptr) {
        return true;
    }
    if (!g_mpv.loaded()) {
        g_mpv = mpv::api::load();
    }
    if (!g_mpv.loaded()) {
        setStatus(L"mpv-2.dll tidak ditemukan. Taruh file itu di sebelah Sora.exe.");
        return false;
    }

    g_mpv_handle = g_mpv.create();
    if (g_mpv_handle == nullptr) {
        setStatus(L"mpv_create gagal.");
        return false;
    }

    // Embed mpv into the child window before mpv_initialize().
    const auto handle_value = std::to_string(reinterpret_cast<uintptr_t>(g_video));
    g_mpv.set_option_string(g_mpv_handle, "wid", handle_value.c_str());
    g_mpv.set_option_string(g_mpv_handle, "terminal", "no");
    g_mpv.set_option_string(g_mpv_handle, "osc", "yes");
    g_mpv.set_option_string(g_mpv_handle, "input-default-bindings", "yes");
    g_mpv.set_option_string(g_mpv_handle, "keep-open", "yes");

    if (g_mpv.initialize(g_mpv_handle) < 0) {
        setStatus(L"mpv_initialize gagal.");
        g_mpv.terminate_destroy(g_mpv_handle);
        g_mpv_handle = nullptr;
        return false;
    }
    return true;
}

void playUrl(const std::string& url) {
    if (!startMpv()) {
        return;
    }
    const char* command[] = {"loadfile", url.c_str(), nullptr};
    if (g_mpv.command(g_mpv_handle, command) < 0) {
        setStatus(L"mpv menolak URL tersebut.");
        return;
    }
    setBusy(false);
}

// ------------------------------------------------------------------- engine

#ifdef SORA_HAS_NUVIO_ENGINE

bool ensureEngine() {
    if (g_engine != nullptr) {
        return true;
    }

    const std::wstring root = engineDirectory();
    ensureDirectory(root);
    const std::wstring data = root + L"\\data";
    const std::wstring cache = root + L"\\cache";
    CreateDirectoryW(data.c_str(), nullptr);
    CreateDirectoryW(cache.c_str(), nullptr);

    const std::string dataUtf8 = toUtf8(data);
    const std::string cacheUtf8 = toUtf8(cache);

    nuvio_engine_config config{};
    nuvio_engine_config_init(&config);
    config.data_directory = dataUtf8.c_str();
    config.cache_directory = cacheUtf8.c_str();
    config.torrent_profile = NUVIO_ENGINE_TORRENT_PROFILE_BALANCED;

    const nuvio_engine_status status = nuvio_engine_create(&config, &g_engine);
    if (status != NUVIO_ENGINE_STATUS_OK) {
        setStatus(L"Engine gagal disiapkan: " + fromUtf8(nuvio_engine_status_message(status)));
        g_engine = nullptr;
        return false;
    }
    return true;
}

/// Waits for one event of `type` whose request id matches (0 = any request).
/// Torrent errors that belong to the awaited request abort the wait.
bool waitForEvent(nuvio_engine* engine, uint32_t type, uint64_t request_id,
                  nuvio_engine_event& out, DWORD timeout_ms, std::wstring& error) {
    const ULONGLONG deadline = GetTickCount64() + timeout_ms;
    nuvio_engine_event event{};
    nuvio_engine_event_init(&event);

    while (GetTickCount64() < deadline) {
        if (nuvio_engine_poll_event(engine, &event) == NUVIO_ENGINE_STATUS_OK) {
            const bool same_request = request_id == 0 || event.request_id == request_id;
            if (same_request && event.type == type) {
                out = event;
                return true;
            }
            if (same_request && event.type == NUVIO_ENGINE_EVENT_TORRENT_ERROR) {
                error = L"Torrent error: " + fromUtf8(event.message);
                return false;
            }
        }
        Sleep(50);
    }
    error = L"Timeout menunggu engine.";
    return false;
}

bool hasVideoExtension(const std::string& path) {
    static const std::vector<std::string> extensions = {
        ".mp4", ".mkv", ".webm", ".m4v", ".mov", ".avi", ".ts",
    };
    std::string lowered = path;
    std::transform(lowered.begin(), lowered.end(), lowered.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return std::any_of(extensions.begin(), extensions.end(), [&](const std::string& ext) {
        return lowered.size() >= ext.size() &&
               lowered.compare(lowered.size() - ext.size(), ext.size(), ext) == 0;
    });
}

/// Resolves a magnet to a loopback URL. Returns false and fills `error`.
bool resolveMagnet(const std::string& magnet, std::string& url, std::string& path,
                   std::wstring& error) {
    if (!ensureEngine()) {
        error = L"Engine tidak tersedia.";
        return false;
    }

    nuvio_engine_torrent_request request{};
    nuvio_engine_torrent_request_init(&request);
    request.magnet_uri = magnet.c_str();
    request.source_type = NUVIO_ENGINE_TORRENT_SOURCE_MAGNET;

    uint64_t request_id = 0;
    nuvio_engine_status status = nuvio_engine_add_torrent(g_engine, &request, &request_id);
    if (status != NUVIO_ENGINE_STATUS_OK) {
        error = fromUtf8(nuvio_engine_status_message(status));
        return false;
    }

    nuvio_engine_event event{};
    if (!waitForEvent(g_engine, NUVIO_ENGINE_EVENT_TORRENT_METADATA_READY, request_id, event,
                      120'000, error)) {
        return false;
    }

    const std::string torrent_id(event.torrent_id);

    size_t file_count = 0;
    status = nuvio_engine_get_file_count(g_engine, torrent_id.c_str(), &file_count);
    if (status != NUVIO_ENGINE_STATUS_OK || file_count == 0) {
        error = L"Torrent tidak berisi file.";
        return false;
    }

    bool have_best = false;
    nuvio_engine_file best{};
    nuvio_engine_file_init(&best);
    bool best_is_video = false;

    for (size_t index = 0; index < file_count; ++index) {
        nuvio_engine_file file{};
        nuvio_engine_file_init(&file);
        if (nuvio_engine_get_file(g_engine, torrent_id.c_str(), index, &file) !=
            NUVIO_ENGINE_STATUS_OK) {
            continue;
        }
        if (file.size == 0) {
            continue;
        }
        const bool is_video = hasVideoExtension(file.path);
        // Prefer a video file over any other file; within that group, largest wins.
        const bool better = !have_best || (is_video && !best_is_video) ||
                            (is_video == best_is_video && file.size > best.size);
        if (better) {
            best = file;
            best_is_video = is_video;
            have_best = true;
        }
    }

    if (!have_best) {
        error = L"Torrent tidak berisi file yang bisa diputar.";
        return false;
    }

    path = best.path;

    nuvio_engine_stream_request stream_request{};
    nuvio_engine_stream_request_init(&stream_request);
    stream_request.torrent_id = torrent_id.c_str();
    stream_request.file_index = best.index;
    stream_request.filename_hint = best.path;

    status = nuvio_engine_prepare_stream(g_engine, &stream_request, &request_id);
    if (status != NUVIO_ENGINE_STATUS_OK) {
        error = fromUtf8(nuvio_engine_status_message(status));
        return false;
    }

    if (!waitForEvent(g_engine, NUVIO_ENGINE_EVENT_STREAM_PREPARED, request_id, event, 120'000,
                      error)) {
        return false;
    }

    url = event.stream_url;
    return !url.empty();
}

#endif  // SORA_HAS_NUVIO_ENGINE

// ----------------------------------------------------------------------- UI

void layoutChildren(HWND window) {
    RECT client{};
    GetClientRect(window, &client);
    const int width = client.right - client.left;
    const int height = client.bottom - client.top;

    const int padding = 12;
    const int button_width = 84;

    if (g_input != nullptr) {
        MoveWindow(g_input, padding, padding, std::max(0, width - button_width - padding * 3),
                   kRowHeight - padding, TRUE);
        MoveWindow(g_play, width - button_width - padding, padding, button_width,
                   kRowHeight - padding, TRUE);
        MoveWindow(g_status, padding, kRowHeight, std::max(0, width - padding * 2), kStatusHeight,
                   TRUE);
        MoveWindow(g_video, 0, kRowHeight + kStatusHeight, width,
                   std::max(0, height - kRowHeight - kStatusHeight), TRUE);
    }
}

void onPlay() {
    const std::wstring text = inputText();
    if (text.empty()) {
        setStatus(L"Isi magnet atau URL dulu.");
        return;
    }

    const std::string input = toUtf8(text);
    setBusy(true);

    if (!startsWithIgnoreCase(input, "magnet:")) {
        setStatus(L"Memutar URL langsung…");
        playUrl(input);
        return;
    }

#ifdef SORA_HAS_NUVIO_ENGINE
    setStatus(L"Mengambil metadata torrent…");
    std::string url;
    std::string path;
    std::wstring error;
    if (resolveMagnet(input, url, path, error)) {
        setStatus(L"Memutar " + fromUtf8(path));
        playUrl(url);
    } else {
        setStatus(L"Gagal: " + error);
        setBusy(false);
    }
#else
    setStatus(L"Magnet butuh nuvio-engine. Bangun ulang dengan -DNUVIO_ENGINE_DIR=…");
    setBusy(false);
#endif
}

LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
        case WM_CREATE: {
            g_input = CreateWindowExW(
                WS_EX_CLIENTEDGE, L"EDIT", L"",
                WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_LEFT, 0, 0, 0, 0, window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIdInput)),
                GetModuleHandleW(nullptr), nullptr);

            g_play = CreateWindowExW(
                0, L"BUTTON", L"Putar", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON | BS_DEFPUSHBUTTON, 0,
                0, 0, 0, window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIdPlay)),
                GetModuleHandleW(nullptr), nullptr);

            g_status = CreateWindowExW(
                0, L"STATIC", L"Tempel magnet atau URL file video.",
                WS_CHILD | WS_VISIBLE | SS_LEFT, 0, 0, 0, 0, window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIdStatus)),
                GetModuleHandleW(nullptr), nullptr);

            g_video = CreateWindowExW(
                0, L"STATIC", L"", WS_CHILD | WS_VISIBLE | SS_BLACKRECT, 0, 0, 0, 0, window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(kIdVideo)),
                GetModuleHandleW(nullptr), nullptr);

            const HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
            for (HWND child : {g_input, g_play, g_status}) {
                SendMessageW(child, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
            }

            // Keyboard focus goes to the paste target, not to mpv.
            SetFocus(g_input);
            return 0;
        }

        case WM_SIZE:
            layoutChildren(window);
            return 0;

        case WM_COMMAND:
            if (LOWORD(wparam) == kIdPlay && HIWORD(wparam) == BN_CLICKED) {
                onPlay();
                return 0;
            }
            return 0;

        case WM_DESTROY:
            if (g_mpv_handle != nullptr) {
                g_mpv.terminate_destroy(g_mpv_handle);
                g_mpv_handle = nullptr;
            }
            g_mpv.unload();
#ifdef SORA_HAS_NUVIO_ENGINE
            if (g_engine != nullptr) {
                nuvio_engine_destroy(g_engine);
                g_engine = nullptr;
            }
#endif
            PostQuitMessage(0);
            return 0;

        default:
            return DefWindowProcW(window, message, wparam, lparam);
    }
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show_command) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    const wchar_t* class_name = L"SoraMainWindow";
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = windowProc;
    window_class.hInstance = instance;
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.hbrBackground = CreateSolidBrush(RGB(0x08, 0x08, 0x0B));
    window_class.lpszClassName = class_name;

    if (RegisterClassExW(&window_class) == 0) {
        MessageBoxW(nullptr, L"RegisterClassEx gagal.", L"Sora", MB_ICONERROR);
        return 1;
    }

    g_window = CreateWindowExW(
        0, class_name, L"Sora", WS_OVERLAPPEDWINDOW | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT,
        1100, 680, nullptr, nullptr, instance, nullptr);

    if (g_window == nullptr) {
        MessageBoxW(nullptr, L"CreateWindowEx gagal.", L"Sora", MB_ICONERROR);
        return 1;
    }

    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return 0;
}
