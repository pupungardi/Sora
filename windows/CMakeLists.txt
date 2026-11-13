cmake_minimum_required(VERSION 3.22)

project(Sora LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT WIN32)
    message(FATAL_ERROR "This target is Windows-only. Use android/ or ios/ on other hosts.")
endif()

# ---------------------------------------------------------------------------
# nuvio-engine (optional at configure time)
#
# Unpack nuvio-engine-windows-x86_64.zip from
#   native/nuvio-engine/platform/windows/dist/
# and point this at the unpacked folder, e.g.
#   cmake -S windows -B build -DNUVIO_ENGINE_DIR=C:/deps/nuvio-engine-windows-x86_64
#
# The package ships bin/nuvio_engine.dll, lib/libnuvio_engine.dll.a (MinGW
# import library) and lib/nuvio_engine.def (for `lib /def:` under MSVC).
# Without the package Sora still builds and plays direct URLs through libmpv;
# magnet support is compiled out.
# ---------------------------------------------------------------------------
set(NUVIO_ENGINE_DIR "" CACHE PATH "Unpacked nuvio-engine Windows package")

set(SORA_ENGINE_IMPORT_LIB "")
if(NUVIO_ENGINE_DIR)
    if(MSVC)
        set(_candidate "${NUVIO_ENGINE_DIR}/lib/nuvio_engine.lib")
    else()
        set(_candidate "${NUVIO_ENGINE_DIR}/lib/libnuvio_engine.dll.a")
    endif()

    if(EXISTS "${_candidate}")
        set(SORA_ENGINE_IMPORT_LIB "${_candidate}")
        message(STATUS "nuvio-engine import library: ${_candidate}")
    else()
        message(WARNING
            "NUVIO_ENGINE_DIR is set but ${_candidate} is missing. "
            "Magnet support will be compiled out.")
    endif()
endif()

add_executable(Sora WIN32
    src/main.cpp
)

target_compile_definitions(Sora PRIVATE UNICODE _UNICODE)
target_link_libraries(Sora PRIVATE user32 gdi32 shell32 ole32)

if(SORA_ENGINE_IMPORT_LIB)
    target_compile_definitions(Sora PRIVATE SORA_HAS_NUVIO_ENGINE=1)
    target_include_directories(Sora PRIVATE "${NUVIO_ENGINE_DIR}/include")
    target_link_libraries(Sora PRIVATE "${SORA_ENGINE_IMPORT_LIB}")

    # Keep the runtime DLLs next to Sora.exe.
    add_custom_command(TARGET Sora POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${NUVIO_ENGINE_DIR}/bin/nuvio_engine.dll"
            "$<TARGET_FILE_DIR:Sora>"
        VERBATIM)
endif()

# libmpv is loaded with LoadLibrary("mpv-2.dll") at runtime, so there is no
# import library and no link-time dependency. Copy it next to the exe if it is
# reachable from MPV_DLL.
set(MPV_DLL "" CACHE FILEPATH "Path to mpv-2.dll to copy next to Sora.exe")
if(MPV_DLL AND EXISTS "${MPV_DLL}")
    add_custom_command(TARGET Sora POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${MPV_DLL}"
            "$<TARGET_FILE_DIR:Sora>"
        VERBATIM)
endif()
