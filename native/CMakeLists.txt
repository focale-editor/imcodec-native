cmake_minimum_required(VERSION 3.25)
project(imcodec_native LANGUAGES C CXX)

include(FetchContent)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)
set(CMAKE_SKIP_INSTALL_RULES ON)

include(cmake/sources.cmake)
include(cmake/raster_engines.cmake)

# Portable scalar AV1 avoids NASM and architecture-specific assembler setup.
# Native builds still run codec work in isolates; Web builds need no pthreads.
set(AOM_TARGET_CPU generic CACHE STRING "" FORCE)
set(ENABLE_DOCS OFF CACHE BOOL "" FORCE)
set(ENABLE_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(ENABLE_TOOLS OFF CACHE BOOL "" FORCE)
set(CONFIG_MULTITHREAD 0 CACHE STRING "" FORCE)
set(CONFIG_AV1_ENCODER 1 CACHE STRING "" FORCE)
set(CONFIG_AV1_DECODER 1 CACHE STRING "" FORCE)
set(ENABLE_NASM OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(aom)
# libheif calls find_package(AOM); keep that lookup on the bundled target even
# when the platform SDK exposes its own package configuration.
add_library(AOM::aom ALIAS aom)
set(AOM_FOUND TRUE)
set(AOM_DECODER_FOUND TRUE)
set(AOM_ENCODER_FOUND TRUE)
set(AOM_INCLUDE_DIRS "${aom_SOURCE_DIR}")
set(AOM_LIBRARIES aom)

set(ENABLE_SDL OFF CACHE BOOL "" FORCE)
set(ENABLE_DECODER OFF CACHE BOOL "" FORCE)
set(ENABLE_ENCODER OFF CACHE BOOL "" FORCE)
set(ENABLE_SIMD OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(libde265)
target_include_directories(de265 PRIVATE "${libde265_BINARY_DIR}")

set(BUILD_KVAZAAR_BINARY OFF CACHE BOOL "" FORCE)
set(USE_CRYPTO OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(kvazaar)
if(MSVC)
  target_compile_definitions(kvazaar PRIVATE _USE_MATH_DEFINES)
else()
  target_compile_definitions(kvazaar PRIVATE _GNU_SOURCE)
  target_compile_options(kvazaar PRIVATE $<$<COMPILE_LANGUAGE:C>:-std=gnu11>)
endif()

# Resolve libheif's optional engines exclusively to the bundled CMake targets.
set(AOM_INCLUDE_DIR "${aom_SOURCE_DIR}" CACHE PATH "" FORCE)
set(AOM_LIBRARY aom CACHE STRING "" FORCE)
set(aom_usage_flag_exists 1 CACHE INTERNAL "" FORCE)
set(LIBDE265_INCLUDE_DIR "${libde265_SOURCE_DIR}" CACHE PATH "" FORCE)
set(LIBDE265_LIBRARY de265 CACHE STRING "" FORCE)
set(KVAZAAR_INCLUDE_DIR "${kvazaar_SOURCE_DIR}/src" CACHE PATH "" FORCE)
set(KVAZAAR_LIBRARY kvazaar CACHE STRING "" FORCE)
set(HAVE_KVAZAAR_ENABLE_LOGGING 1 CACHE INTERNAL "" FORCE)
set(ENABLE_PLUGIN_LOADING OFF CACHE BOOL "" FORCE)
set(ENABLE_MULTITHREADING_SUPPORT OFF CACHE BOOL "" FORCE)
set(ENABLE_PARALLEL_TILE_DECODING OFF CACHE BOOL "" FORCE)
set(WITH_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WITH_GDK_PIXBUF OFF CACHE BOOL "" FORCE)
set(BUILD_DOCUMENTATION OFF CACHE BOOL "" FORCE)
set(WITH_HEADER_COMPRESSION OFF CACHE BOOL "" FORCE)
set(WITH_LIBSHARPYUV OFF CACHE BOOL "" FORCE)
foreach(codec LIBDE265 AOM_DECODER AOM_ENCODER KVAZAAR)
  set(WITH_${codec} ON CACHE BOOL "" FORCE)
  set(WITH_${codec}_PLUGIN OFF CACHE BOOL "" FORCE)
endforeach()
foreach(codec X265 X264 OpenH264_DECODER DAV1D SvtEnc RAV1E JPEG_DECODER
    JPEG_ENCODER OpenJPEG_ENCODER OpenJPEG_DECODER FFMPEG_DECODER
    OPENJPH_ENCODER UVG266 VVDEC VVENC UNCOMPRESSED_CODEC WEBCODECS)
  set(WITH_${codec} OFF CACHE BOOL "" FORCE)
endforeach()
FetchContent_MakeAvailable(libheif)
target_include_directories(heif PRIVATE "${libde265_BINARY_DIR}")
target_compile_definitions(heif PRIVATE LIBDE265_STATIC_BUILD KVZ_STATIC_LIB PUBLIC LIBHEIF_STATIC_BUILD)
if(MSVC)
  # Upstream unconditionally publishes HAVE_VISIBILITY, but its GNU attribute
  # is not valid with the static-library API path on Microsoft's compiler.
  foreach(property COMPILE_DEFINITIONS INTERFACE_COMPILE_DEFINITIONS)
    get_target_property(definitions heif ${property})
    list(REMOVE_ITEM definitions HAVE_VISIBILITY)
    set_property(TARGET heif PROPERTY ${property} "${definitions}")
  endforeach()
  target_compile_definitions(heif PUBLIC HAVE_VISIBILITY=0)
endif()
if(EMSCRIPTEN)
  target_compile_options(heif PRIVATE -fexceptions)
  target_compile_options(de265 PRIVATE -fexceptions)
  # Only this translation unit selects libheif's optional Embind facade. Use
  # its C-only path: ImcodecNative exports its own smaller, stable C ABI.
  set_source_files_properties("${libheif_SOURCE_DIR}/libheif/api/libheif/heif.cc"
    DIRECTORY "${libheif_SOURCE_DIR}/libheif"
    PROPERTIES COMPILE_DEFINITIONS __EMSCRIPTEN_STANDALONE_WASM__)
endif()

# Preserve the alpha plane even when HEIC colour samples use lossy compression.
# This narrowly scoped patch is checked against the pinned upstream source.
set(kvazaar_plugin "${libheif_SOURCE_DIR}/libheif/plugins/encoder_kvazaar.cc")
file(READ "${kvazaar_plugin}" kvazaar_plugin_source)
set(original "config->lossless = encoder->lossless ? 1 : 0;")
set(patched "config->lossless = (encoder->lossless || input_class == heif_image_input_class_alpha) ? 1 : 0;")
string(FIND "${kvazaar_plugin_source}" "${patched}" already_patched)
if(already_patched EQUAL -1)
  string(FIND "${kvazaar_plugin_source}" "${original}" patch_position)
  if(patch_position EQUAL -1)
    message(FATAL_ERROR "The pinned Kvazaar alpha patch no longer applies")
  endif()
  string(REPLACE "${original}" "${patched}" kvazaar_plugin_source "${kvazaar_plugin_source}")
  file(WRITE "${kvazaar_plugin}" "${kvazaar_plugin_source}")
endif()

# libheif reuses its AOM encoder for colour and alpha images. Release the
# preceding context before initializing another one; its destructor only frees
# the last context. Keep this patch checked against the pinned upstream source.
set(aom_plugin "${libheif_SOURCE_DIR}/libheif/plugins/encoder_aom.cc")
file(READ "${aom_plugin}" aom_plugin_source)
set(original "  aom_codec_ctx_t codec;")
set(patched "  aom_codec_ctx_t codec{};")
string(FIND "${aom_plugin_source}" "${patched}" already_patched)
if(already_patched EQUAL -1)
  string(FIND "${aom_plugin_source}" "${original}" patch_position)
  if(patch_position EQUAL -1)
    message(FATAL_ERROR "The pinned AOM context initialization patch no longer applies")
  endif()
  string(REPLACE "${original}" "${patched}" aom_plugin_source "${aom_plugin_source}")
endif()
set(original "  // allocate aom_codec_ctx_t\n  if (aom_codec_enc_init(&codec, iface, &cfg, encoder_flags)) {")
set(patched "  // Release the preceding colour/alpha context before reinitialization.\n  if (codec.priv != nullptr) {\n    aom_codec_destroy(&codec);\n  }\n\n  // allocate aom_codec_ctx_t\n  if (aom_codec_enc_init(&codec, iface, &cfg, encoder_flags)) {")
string(FIND "${aom_plugin_source}" "${patched}" already_patched)
if(already_patched EQUAL -1)
  string(FIND "${aom_plugin_source}" "${original}" patch_position)
  if(patch_position EQUAL -1)
    message(FATAL_ERROR "The pinned AOM context lifetime patch no longer applies")
  endif()
  string(REPLACE "${original}" "${patched}" aom_plugin_source "${aom_plugin_source}")
endif()
file(WRITE "${aom_plugin}" "${aom_plugin_source}")

# The HEIC plugin also reuses its encoder for colour and alpha. Release both
# the encoder and its configuration before replacing their owning pointers.
file(READ "${kvazaar_plugin}" kvazaar_plugin_source)
set(original "  const kvz_api* api = encoder->api = kvz_api_get(bit_depth);")
set(patched "  // Release the preceding colour/alpha context before reinitialization.\n  if (encoder->kvzencoder != nullptr) {\n    encoder->api->encoder_close(encoder->kvzencoder);\n    encoder->kvzencoder = nullptr;\n  }\n  if (encoder->config != nullptr) {\n    encoder->api->config_destroy(encoder->config);\n    encoder->config = nullptr;\n  }\n\n  const kvz_api* api = encoder->api = kvz_api_get(bit_depth);")
string(FIND "${kvazaar_plugin_source}" "${patched}" already_patched)
if(already_patched EQUAL -1)
  string(FIND "${kvazaar_plugin_source}" "${original}" patch_position)
  if(patch_position EQUAL -1)
    message(FATAL_ERROR "The pinned Kvazaar context lifetime patch no longer applies")
  endif()
  string(REPLACE "${original}" "${patched}" kvazaar_plugin_source "${kvazaar_plugin_source}")
  file(WRITE "${kvazaar_plugin}" "${kvazaar_plugin_source}")
endif()

foreach(engine AOM_ENCODER AOM_DECODER LIBDE265 KVAZAAR)
  get_directory_property(engine_found DIRECTORY "${libheif_SOURCE_DIR}" DEFINITION ${engine}_FOUND)
  if(NOT engine_found)
    message(FATAL_ERROR "The bundled ${engine} engine was not enabled")
  endif()
endforeach()

foreach(option WEBP_BUILD_ANIM_UTILS WEBP_BUILD_CWEBP WEBP_BUILD_DWEBP
    WEBP_BUILD_GIF2WEBP WEBP_BUILD_IMG2WEBP WEBP_BUILD_VWEBP WEBP_BUILD_WEBPINFO
    WEBP_BUILD_WEBPMUX WEBP_BUILD_EXTRAS WEBP_BUILD_LIBWEBPMUX WEBP_USE_THREAD)
  set(${option} OFF CACHE BOOL "" FORCE)
endforeach()
FetchContent_MakeAvailable(libwebp)

foreach(option TOOLS DEVTOOLS DOXYGEN MANPAGES BENCHMARK EXAMPLES JNI SJPEG
    OPENEXR VIEWERS TCMALLOC PLUGINS TRANSCODE_JPEG WASM_THREADS)
  set(JPEGXL_ENABLE_${option} OFF CACHE BOOL "" FORCE)
endforeach()
set(JPEGXL_ENABLE_SKCMS ON CACHE BOOL "" FORCE)
set(JPEGXL_BUNDLE_LIBPNG OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(libjxl)
imcodec_declare_jxl_dependencies()
FetchContent_MakeAvailable(brotli highway skcms)
add_subdirectory("${libjxl_SOURCE_DIR}" "${libjxl_BINARY_DIR}" EXCLUDE_FROM_ALL)

if(EMSCRIPTEN)
  add_executable(imcodec_native src/imcodec_native.cpp src/png.cpp src/jpeg.cpp src/qoi.cpp src/tiff.cpp src/open_exr.cpp)
  set_target_properties(imcodec_native PROPERTIES SUFFIX .mjs)
  target_compile_options(imcodec_native PRIVATE -fexceptions)
  target_link_options(imcodec_native PRIVATE
    -fexceptions --no-entry
    -sMODULARIZE=1 -sEXPORT_ES6=1 -sENVIRONMENT=web,worker,node
    -sFILESYSTEM=0 -sALLOW_MEMORY_GROWTH=1 -sABORTING_MALLOC=0 -sINITIAL_MEMORY=33554432
    -sMAXIMUM_MEMORY=2147483648 -sSTACK_SIZE=5242880 -sALLOW_TABLE_GROWTH=1
    -sEXPORTED_RUNTIME_METHODS=UTF8ToString,HEAPU8
    -sEXPORTED_FUNCTIONS=_malloc,_free,_imcodec_decode,_imcodec_encode,_imcodec_inspect,_imcodec_result_free,_imcodec_result_number,_imcodec_result_data,_imcodec_result_error,_imcodec_version)
else()
  add_library(imcodec_native SHARED src/imcodec_native.cpp src/png.cpp src/jpeg.cpp src/qoi.cpp src/tiff.cpp src/open_exr.cpp)
  if(ANDROID)
    # Keep the code asset self-contained and compatible with 16 KB page devices.
    target_link_options(imcodec_native PRIVATE
      -Wl,--exclude-libs,ALL,-z,max-page-size=16384
      $<$<CONFIG:Release>:-Wl,--strip-all>)
  elseif(UNIX AND NOT APPLE)
    # Only the stable shim ABI should escape statically linked codec archives.
    target_link_options(imcodec_native PRIVATE -Wl,--exclude-libs,ALL)
  endif()
  if(APPLE)
    set_target_properties(imcodec_native PROPERTIES INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR ON)
  endif()
endif()
target_include_directories(imcodec_native PRIVATE include "${qoi_SOURCE_DIR}" "${libheif_SOURCE_DIR}/libheif/api" "${libheif_BINARY_DIR}")
target_link_libraries(imcodec_native PRIVATE heif jxl webp webpdemux png_static imcodec_jpeg tiff OpenEXR::OpenEXR)
set_target_properties(imcodec_native PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out"
  LIBRARY_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/out"
  RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/out")

option(IMCODEC_BUILD_FIXTURES "Build the synthetic high-depth fixture generator" OFF)
if(IMCODEC_BUILD_FIXTURES AND NOT EMSCRIPTEN)
  add_executable(imcodec_fixture_generator ../tool/fixture_generator.cpp)
  target_include_directories(imcodec_fixture_generator PRIVATE "${libheif_SOURCE_DIR}/libheif/api" "${libheif_BINARY_DIR}")
  target_link_libraries(imcodec_fixture_generator PRIVATE heif)
  add_executable(imcodec_raster_fixture_generator ../tool/raster_fixture_generator.cpp)
  target_link_libraries(imcodec_raster_fixture_generator PRIVATE OpenEXR::OpenEXR imcodec_jpeg)
endif()
