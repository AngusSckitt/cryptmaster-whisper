# Builds whisper.cpp (from WHISPER_SRC) together with the mod's cmwhisper shim.
cmake_minimum_required(VERSION 3.21)
project(cmwhisper CXX C)

set(WHISPER_SRC "" CACHE PATH "whisper.cpp source folder")
if(NOT EXISTS "${WHISPER_SRC}/CMakeLists.txt")
    message(FATAL_ERROR "Set WHISPER_SRC to a whisper.cpp checkout")
endif()

add_subdirectory(${WHISPER_SRC} whisper)

add_library(cmwhisper SHARED cmwhisper.cpp)
target_link_libraries(cmwhisper PRIVATE whisper ggml)
set_target_properties(cmwhisper PROPERTIES RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin/Release")
