cmake_minimum_required(VERSION 3.22)
set(TARGET HarenaDamage)
project(${TARGET})

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(${TARGET} SHARED
    dllmain.cpp
)

target_include_directories(${TARGET} PRIVATE .)
target_link_libraries(${TARGET} PUBLIC UE4SS)

set_target_properties(${TARGET} PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/Mods/${TARGET}/dlls"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/Mods/${TARGET}/dlls"
)
