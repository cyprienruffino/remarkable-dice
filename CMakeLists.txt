cmake_minimum_required(VERSION 3.16)
project(dice LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# The backend, started by AppLoad as backend/entry
add_executable(entry backend/main.cpp)
target_include_directories(entry PRIVATE backend)

# The frontend, packed into resources.rcc
if(NOT RCC_EXECUTABLE AND DEFINED ENV{RCC_EXECUTABLE})
    set(RCC_EXECUTABLE $ENV{RCC_EXECUTABLE})
endif()
find_program(RCC_EXECUTABLE NAMES rcc REQUIRED)
file(GLOB_RECURSE QML_FILES CONFIGURE_DEPENDS ${CMAKE_SOURCE_DIR}/ui/*)
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/resources.rcc
    COMMAND ${RCC_EXECUTABLE} --binary -o ${CMAKE_BINARY_DIR}/resources.rcc ${CMAKE_SOURCE_DIR}/application.qrc
    DEPENDS ${CMAKE_SOURCE_DIR}/application.qrc ${QML_FILES}
)
add_custom_target(resources ALL DEPENDS ${CMAKE_BINARY_DIR}/resources.rcc)

# The AppLoad application directory: cmake --install <build> --prefix dist/dice
install(TARGETS entry DESTINATION backend)
install(FILES manifest.json icon.png ${CMAKE_BINARY_DIR}/resources.rcc DESTINATION .)
