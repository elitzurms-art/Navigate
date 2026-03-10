cmake_minimum_required(VERSION 3.14)

# מנוע ניתוח תוואי שטח — ספרייה דינמית (DLL)
add_library(terrain_engine SHARED terrain_engine.cpp)

# הגדרות קומפילציה
target_compile_features(terrain_engine PUBLIC cxx_std_17)
target_compile_definitions(terrain_engine PRIVATE TERRAIN_ENGINE_EXPORTS)
target_compile_options(terrain_engine PRIVATE /W4 /wd"4100" /EHsc)

# התקנה — DLL ליד ה-exe של האפליקציה
install(TARGETS terrain_engine
  RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
