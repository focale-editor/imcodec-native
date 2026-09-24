# AOM reuses HAVE_UNISTD_H in its cache. Probe under our own name before
# configuring libraries whose generated headers depend on this platform test.
include(CheckIncludeFile)
check_include_file(unistd.h IMCODEC_HAVE_UNISTD_H)
set(HAVE_UNISTD_H ${IMCODEC_HAVE_UNISTD_H})

# Bundle every dependency: platform SDK libraries must not enter code assets.
set(ZLIB_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZLIB_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(ZLIB_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(zlib)
add_library(ZLIB::ZLIB ALIAS zlibstatic)
set(ZLIB_FOUND TRUE)
set(ZLIB_INCLUDE_DIRS "${zlib_SOURCE_DIR};${zlib_BINARY_DIR}")
set(ZLIB_LIBRARIES zlibstatic)
foreach(option PNG_SHARED PNG_TESTS PNG_TOOLS PNG_EXECUTABLES PNG_FRAMEWORK)
  set(${option} OFF CACHE BOOL "" FORCE)
endforeach()
FetchContent_MakeAvailable(libpng)

# libjpeg-turbo explicitly requires a standalone CMake project. Forward the
# selected target toolchain and expose only its static libjpeg API to the shim.
FetchContent_MakeAvailable(libjpeg)
include(ExternalProject)
set(jpeg_arguments -DCMAKE_BUILD_TYPE=Release -DENABLE_SHARED=OFF
  -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF -DWITH_TESTS=OFF
  -DWITH_SIMD=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DCMAKE_C_VISIBILITY_PRESET=hidden)
foreach(variable CMAKE_TOOLCHAIN_FILE CMAKE_C_COMPILER CMAKE_CXX_COMPILER
    CMAKE_AR CMAKE_RANLIB CMAKE_SYSROOT CMAKE_SYSTEM_NAME CMAKE_SYSTEM_PROCESSOR
    CMAKE_OSX_ARCHITECTURES CMAKE_OSX_SYSROOT CMAKE_OSX_DEPLOYMENT_TARGET
    CMAKE_MSVC_RUNTIME_LIBRARY ANDROID_ABI ANDROID_PLATFORM ANDROID_STL)
  if(DEFINED ${variable} AND NOT "${${variable}}" STREQUAL "")
    list(APPEND jpeg_arguments "-D${variable}=${${variable}}")
  endif()
endforeach()
set(jpeg_archive "${libjpeg_BINARY_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}jpeg${CMAKE_STATIC_LIBRARY_SUFFIX}")
if(MSVC)
  set(jpeg_archive "${libjpeg_BINARY_DIR}/jpeg-static.lib")
  if(CMAKE_CONFIGURATION_TYPES)
    set(jpeg_archive "${libjpeg_BINARY_DIR}/Release/jpeg-static.lib")
  endif()
endif()
file(MAKE_DIRECTORY "${libjpeg_BINARY_DIR}")
ExternalProject_Add(imcodec_jpeg_build SOURCE_DIR "${libjpeg_SOURCE_DIR}"
  BINARY_DIR "${libjpeg_BINARY_DIR}" DOWNLOAD_COMMAND "" UPDATE_COMMAND ""
  CMAKE_GENERATOR_PLATFORM "${CMAKE_GENERATOR_PLATFORM}"
  CMAKE_GENERATOR_TOOLSET "${CMAKE_GENERATOR_TOOLSET}"
  CMAKE_ARGS ${jpeg_arguments}
  BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --config Release --target jpeg-static --parallel 4
  INSTALL_COMMAND "" BUILD_BYPRODUCTS "${jpeg_archive}")
add_library(imcodec_jpeg STATIC IMPORTED GLOBAL)
set_target_properties(imcodec_jpeg PROPERTIES IMPORTED_LOCATION "${jpeg_archive}"
  INTERFACE_INCLUDE_DIRECTORIES "${libjpeg_SOURCE_DIR}/src;${libjpeg_BINARY_DIR}")
add_dependencies(imcodec_jpeg imcodec_jpeg_build)
add_library(JPEG::JPEG ALIAS imcodec_jpeg)
list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/modules")

# TIFF uses the same pinned zlib and JPEG archives. Disable unrelated optional
# system codecs so cross-compilation cannot discover host-only dependencies.
set(JPEG_FOUND TRUE)
set(JPEG_INCLUDE_DIR "${libjpeg_SOURCE_DIR}/src" CACHE PATH "" FORCE)
set(JPEG_LIBRARY imcodec_jpeg CACHE STRING "" FORCE)
set(JPEG_LIBRARIES imcodec_jpeg)
set(jpeg-prefer-standard ON CACHE BOOL "" FORCE)
set(HAVE_JPEGTURBO_DUAL_MODE_8 TRUE CACHE INTERNAL "" FORCE)
set(HAVE_JPEGTURBO_DUAL_MODE_12 TRUE CACHE INTERNAL "" FORCE)
foreach(option tiff-tools tiff-tests tiff-contrib tiff-docs tiff-install
    tiff-cxx tiff-opengl jbig lerc lzma zstd webp libdeflate jpeg12)
  set(${option} OFF CACHE BOOL "" FORCE)
endforeach()
set(jpeg ON CACHE BOOL "" FORCE)
set(zlib ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(libtiff)
add_dependencies(tiff imcodec_jpeg_build)

FetchContent_MakeAvailable(qoi)
set(LIBDEFLATE_BUILD_SHARED_LIB OFF CACHE BOOL "" FORCE)
set(LIBDEFLATE_BUILD_GZIP OFF CACHE BOOL "" FORCE)
set(LIBDEFLATE_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(libdeflate)
if(ANDROID AND CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64" AND
    CMAKE_C_COMPILER_ID STREQUAL "Clang" AND CMAKE_C_COMPILER_VERSION VERSION_LESS 20)
  # NDK r28's arm_neon.h passes polynomial vectors to integer intrinsics.
  target_compile_options(libdeflate_static PRIVATE -flax-vector-conversions=integer)
endif()
set(IMATH_INSTALL OFF CACHE BOOL "" FORCE)
set(IMATH_INSTALL_PKG_CONFIG OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(imath)
foreach(option OPENEXR_INSTALL OPENEXR_INSTALL_PKG_CONFIG OPENEXR_BUILD_TOOLS
    OPENEXR_BUILD_EXAMPLES OPENEXR_ENABLE_THREADING OPENEXR_TEST_LIBRARIES
    OPENEXR_TEST_TOOLS OPENEXR_TEST_PYTHON)
  set(${option} OFF CACHE BOOL "" FORCE)
endforeach()
set(OPENEXR_FORCE_INTERNAL_IMATH ON CACHE BOOL "" FORCE)
set(OPENEXR_FORCE_INTERNAL_OPENJPH ON CACHE BOOL "" FORCE)
set(OPENEXR_FORCE_INTERNAL_DEFLATE ON CACHE BOOL "" FORCE)
set(EXR_DEFLATE_LIB libdeflate::libdeflate_static)
set(EXR_DEFLATE_VERSION 1.26)
if(EMSCRIPTEN)
  # All OpenEXR translation units that can throw must use the bridge's EH mode.
  add_compile_options($<$<COMPILE_LANGUAGE:CXX>:-fexceptions>)
endif()
FetchContent_MakeAvailable(openexr)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  # OpenEXRCore's strict C11 sources use glibc's endian conversion helpers.
  target_compile_definitions(OpenEXRCore PRIVATE _DEFAULT_SOURCE)
endif()
if(EMSCRIPTEN)
  # OpenEXR's DWA classifier calls the POSIX function without strings.h.
  target_compile_options(OpenEXRCore PRIVATE -include strings.h)
  target_compile_definitions(OpenEXRCore PRIVATE _POSIX_C_SOURCE=200809L)
endif()
