cmake_minimum_required(VERSION 3.16)
project(DataSipper VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# DataSipper standalone build
# This builds the core DataSipper components without full Chromium integration
# for testing, validation, and demonstration purposes

# Find required packages
find_package(PkgConfig REQUIRED)
pkg_check_modules(SQLITE3 REQUIRED sqlite3)

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/mock_chromium
)

# Mock Chromium base library (simplified for standalone build)
add_library(mock_chromium_base STATIC
    mock_chromium/base/time.cc
    mock_chromium/base/files.cc
    mock_chromium/base/logging.cc
    mock_chromium/base/strings.cc
    mock_chromium/url/gurl.cc
    mock_chromium/sql/database.cc
    mock_chromium/net/http.cc
)

# DataSipper core library
add_library(datasipper_core STATIC
    src/chrome/browser/datasipper/network_event.cc
    src/chrome/browser/datasipper/database_schema.cc
    src/chrome/browser/datasipper/database_manager.cc
    src/chrome/browser/datasipper/data_storage_service.cc
    src/chrome/browser/datasipper/stream_filter.cc
    src/chrome/browser/datasipper/data_transformer.cc
)

target_link_libraries(datasipper_core 
    mock_chromium_base 
    ${SQLITE3_LIBRARIES}
    pthread
    z
)

target_include_directories(datasipper_core PRIVATE ${SQLITE3_INCLUDE_DIRS})
target_compile_options(datasipper_core PRIVATE ${SQLITE3_CFLAGS_OTHER})

# DataSipper test executable
add_executable(datasipper_test
    test/datasipper_test_main.cc
    test/network_event_test.cc
    test/database_test.cc
    test/filter_test.cc
    test/transformer_test.cc
)

target_link_libraries(datasipper_test datasipper_core)

# DataSipper demo executable
add_executable(datasipper_demo
    demo/datasipper_demo.cc
)

target_link_libraries(datasipper_demo datasipper_core)

# Install targets
install(TARGETS datasipper_core datasipper_test datasipper_demo
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY src/chrome/browser/datasipper/
    DESTINATION include/datasipper
    FILES_MATCHING PATTERN "*.h"
)

# Package configuration
set(CPACK_PACKAGE_NAME "datasipper")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "DataSipper Network Monitoring Library")
set(CPACK_PACKAGE_DESCRIPTION "Enterprise-grade browser network monitoring and data capture system")
set(CPACK_PACKAGE_CONTACT "DataSipper Team")
set(CPACK_PACKAGE_VENDOR "DataSipper Project")

# DEB package configuration
set(CPACK_DEBIAN_PACKAGE_DEPENDS "libsqlite3-0, zlib1g")
set(CPACK_DEBIAN_PACKAGE_SECTION "devel")
set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")

# RPM package configuration  
set(CPACK_RPM_PACKAGE_GROUP "Development/Libraries")
set(CPACK_RPM_PACKAGE_REQUIRES "sqlite >= 3.0, zlib")

# Archive configuration
set(CPACK_ARCHIVE_COMPONENT_INSTALL ON)

include(CPack)