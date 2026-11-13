// Minimal libmpv surface, loaded at runtime with LoadLibrary.
//
// Sora deliberately does not link against an mpv import library: the official
// Windows builds only ship mpv-2.dll, and users are expected to drop it next to
// Sora.exe. Loading it by hand keeps the build free of a hard link dependency.
#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

namespace mpv {

struct handle;

using create_fn = handle* (*)();
using initialize_fn = int (*)(handle*);
using terminate_destroy_fn = void (*)(handle*);
using command_fn = int (*)(handle*, const char**);
using set_option_string_fn = int (*)(handle*, const char*, const char*);
using set_property_string_fn = int (*)(handle*, const char*, const char*);

struct api {
    HMODULE module = nullptr;
    create_fn create = nullptr;
    initialize_fn initialize = nullptr;
    terminate_destroy_fn terminate_destroy = nullptr;
    command_fn command = nullptr;
    set_option_string_fn set_option_string = nullptr;
    set_property_string_fn set_property_string = nullptr;

    bool loaded() const { return module != nullptr; }

    // Tries mpv-2.dll from the executable directory first, then the plain name
    // so a copy on PATH still works.
    static api load() {
        api out;
        HMODULE module = LoadLibraryExW(L"mpv-2.dll", nullptr,
                                        LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_APPLICATION_DIR);
        if (module == nullptr) {
            module = LoadLibraryW(L"mpv-2.dll");
        }
        if (module == nullptr) {
            return out;
        }

        out.module = module;
        out.create = reinterpret_cast<create_fn>(GetProcAddress(module, "mpv_create"));
        out.initialize = reinterpret_cast<initialize_fn>(GetProcAddress(module, "mpv_initialize"));
        out.terminate_destroy =
            reinterpret_cast<terminate_destroy_fn>(GetProcAddress(module, "mpv_terminate_destroy"));
        out.command = reinterpret_cast<command_fn>(GetProcAddress(module, "mpv_command"));
        out.set_option_string =
            reinterpret_cast<set_option_string_fn>(GetProcAddress(module, "mpv_set_option_string"));
        out.set_property_string =
            reinterpret_cast<set_property_string_fn>(GetProcAddress(module, "mpv_set_property_string"));

        if (out.create == nullptr || out.initialize == nullptr || out.command == nullptr ||
            out.set_option_string == nullptr || out.terminate_destroy == nullptr) {
            FreeLibrary(module);
            return api{};
        }
        return out;
    }

    void unload() {
        if (module != nullptr) {
            FreeLibrary(module);
            *this = api{};
        }
    }
};

}  // namespace mpv
