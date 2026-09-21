cmake_minimum_required(VERSION 3.16)

project(copy_sketch VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Svg)

qt_standard_project_setup(REQUIRES 6.10)

# Content of downloaded design from Figma to Qt or similar
if (EXISTS "${CMAKE_CURRENT_LIST_DIR}/importedcontent/CMakeLists.txt")
    add_subdirectory(${CMAKE_CURRENT_LIST_DIR}/importedcontent)
endif()

qt_add_executable(appcopy_sketch
    main.cpp
)

if(APPLE)
    enable_language(OBJCXX)
    target_sources(appcopy_sketch PRIVATE cursorappearance_mac.mm)
    target_link_libraries(appcopy_sketch PRIVATE "-framework AppKit")
endif()

if(WIN32)
    target_sources(appcopy_sketch PRIVATE cursorappearance_win.cpp)
endif()

qt_add_qml_module(appcopy_sketch
    URI copy_sketch
    QML_FILES
        Main.qml
)

# Keep the full Lucide set available while the interface is still evolving.
# Individual icons can be removed once the visual language has stabilized.
file(GLOB LUCIDE_ICON_FILES CONFIGURE_DEPENDS
    RELATIVE "${CMAKE_CURRENT_LIST_DIR}"
    "${CMAKE_CURRENT_LIST_DIR}/assets/icons/*.svg"
)
qt_add_resources(appcopy_sketch "lucide_icons"
    PREFIX "/"
    FILES ${LUCIDE_ICON_FILES}
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(appcopy_sketch PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.appcopy_sketch
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appcopy_sketch
    PRIVATE Qt6::Quick Qt6::Svg
)

install(TARGETS appcopy_sketch
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
