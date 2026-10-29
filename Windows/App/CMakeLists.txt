# Vikey.exe: tray app + hooks. Built only on Windows (MSVC).
set(VIKEY_VERSION "0.1.0" CACHE STRING "Vikey for Windows version")
add_executable(vikey WIN32 main.cpp Core.cpp Prefs.cpp Vikey.rc)
set_target_properties(vikey PROPERTIES OUTPUT_NAME Vikey)
target_include_directories(vikey PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(vikey PRIVATE UNICODE _UNICODE VIKEY_VERSION="${VIKEY_VERSION}")
target_link_libraries(vikey PRIVATE vikey_engine user32 shell32 gdi32 advapi32 imm32 psapi)
target_link_options(vikey PRIVATE /MANIFEST:NO)
# Live test runner: a window with an edit control, types through SendInput while Vikey runs, reads the text back.
add_executable(vikey_livetest ../Tests/livetest.cpp)
target_include_directories(vikey_livetest PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(vikey_livetest PRIVATE vikey_engine user32)
target_compile_definitions(vikey_livetest PRIVATE UNICODE _UNICODE)
