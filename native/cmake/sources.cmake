# Prefer a source cache prepared by the build hook. Repository checkouts retain
# the exact LGPL archives as an offline fallback; all paths verify the checksum.
function(imcodec_source name)
  cmake_parse_arguments(SOURCE "" "URL;URL_HASH" "" ${ARGN})
  get_filename_component(archive "${SOURCE_URL}" NAME)
  set(prepared "${IMCODEC_NATIVE_SOURCE_DIRECTORY}/${archive}")
  set(bundled "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../../third_party/sources/${archive}")
  if(IMCODEC_NATIVE_SOURCE_DIRECTORY AND EXISTS "${prepared}")
    set(SOURCE_URL "${prepared}")
  elseif(EXISTS "${bundled}")
    set(SOURCE_URL "${bundled}")
  endif()
  FetchContent_Declare(${name} URL "${SOURCE_URL}" URL_HASH "${SOURCE_URL_HASH}" ${SOURCE_UNPARSED_ARGUMENTS})
endfunction()

imcodec_source(libheif
  URL https://github.com/strukturag/libheif/releases/download/v1.21.2/libheif-1.21.2.tar.gz
  URL_HASH SHA256=75f530b7154bc93e7ecf846edfc0416bf5f490612de8c45983c36385aa742b42
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
imcodec_source(libde265
  URL https://github.com/strukturag/libde265/releases/download/v1.1.2/libde265-1.1.2.tar.gz
  URL_HASH SHA256=eaacd1943ab0c452c19f6136a36ca227e6b761b39a81eaca8454d48c147e1f67
  PATCH_COMMAND ${CMAKE_COMMAND} -DIMCODEC_SOURCE_DIR=<SOURCE_DIR> -DIMCODEC_PROJECT=libde265 -P ${CMAKE_CURRENT_LIST_DIR}/namespace_targets.cmake
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
imcodec_source(kvazaar
  URL https://github.com/ultravideo/kvazaar/releases/download/v2.3.2/kvazaar-2.3.2.tar.xz
  URL_HASH SHA256=35e506a6d2be9ae343f17787eb80fa214492b276e9c88b6e93749050ae380070
  PATCH_COMMAND ${CMAKE_COMMAND} -DIMCODEC_SOURCE_DIR=<SOURCE_DIR> -DIMCODEC_PROJECT=kvazaar -P ${CMAKE_CURRENT_LIST_DIR}/namespace_targets.cmake
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
imcodec_source(aom
  URL https://storage.googleapis.com/aom-releases/libaom-3.14.1.tar.gz
  URL_HASH SHA256=44bf90dbd23e734d50e70a8c41c285193922938bd0d3bc2ee56764d181d55ef5
  OVERRIDE_FIND_PACKAGE
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)

imcodec_source(libwebp
  URL https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz
  URL_HASH SHA256=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
imcodec_source(libjxl
  URL https://github.com/libjxl/libjxl/archive/refs/tags/v0.12.0.tar.gz
  URL_HASH SHA256=03e9be69a30be4011f559da75328b6d7cea8ad921fabfbd551ce10bf45cdc992
  SOURCE_SUBDIR __imcodec_download_only
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)

function(imcodec_declare_jxl_dependencies)
  imcodec_source(brotli
    URL https://github.com/google/brotli/archive/028fb5a23661f123017c060daa546b55cf4bde29.tar.gz
    URL_HASH SHA256=0afe09a53c8bad9861c8dd1fc1284308d54f19d2979ba3541cfdcc9b05fe360f
    SOURCE_DIR "${libjxl_SOURCE_DIR}/third_party/brotli"
    SOURCE_SUBDIR __imcodec_download_only
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  imcodec_source(highway
    URL https://github.com/google/highway/archive/457c891775a7397bdb0376bb1031e6e027af1c48.tar.gz
    URL_HASH SHA256=5124b0501c98d9930dbb065bfa1a5bbbd59ce0f12facb7e1e33aaef01a5f1f1a
    SOURCE_DIR "${libjxl_SOURCE_DIR}/third_party/highway"
    SOURCE_SUBDIR __imcodec_download_only
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  imcodec_source(skcms
    URL https://github.com/google/skcms/archive/96d9171c94b937a1b5f0293de7309ac16311b722.tar.gz
    URL_HASH SHA256=9bb4b5bba0b7c04f6c2bce9ff713d61e23c9a20c4945161ae16290498ad74627
    SOURCE_DIR "${libjxl_SOURCE_DIR}/third_party/skcms"
    SOURCE_SUBDIR __imcodec_download_only
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
endfunction()

imcodec_source(zlib
  URL https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz
  URL_HASH SHA256=bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16
  OVERRIDE_FIND_PACKAGE
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)

imcodec_source(libpng
  URL https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.58.tar.gz
  URL_HASH SHA256=a9d4df463d36a6e5f9c29bd6f4967312d17e996c1854f3511f833924eb1993cf
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)

imcodec_source(libjpeg
  URL https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.0/libjpeg-turbo-3.2.0.tar.gz
  URL_HASH SHA256=6f30092cef9fb839779646608f4ee14ae3cbac989c47fa05e841b0841f09878e
  SOURCE_SUBDIR __imcodec_download_only
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)

imcodec_source(libtiff
  URL https://download.osgeo.org/libtiff/tiff-4.7.2.tar.gz
  URL_HASH SHA256=672bd7d10aee4606171afb864f3570b83340f6a33e2c186dc0512f7145ffdf6a
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)

imcodec_source(openexr
  URL https://github.com/AcademySoftwareFoundation/openexr/releases/download/v3.4.14/openexr-3.4.14.tar.gz
  URL_HASH SHA256=174d0d711d963c46eaa7cd2669d6cb1ea52579f43aa2726892f0b9554339ba6b
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)

imcodec_source(imath
  URL https://github.com/AcademySoftwareFoundation/Imath/releases/download/v3.2.3/Imath-3.2.3.tar.gz
  URL_HASH SHA256=72f498e7073890a2a1b870e453908a07c9725f9d1384527043a38578bfb4ef31
  OVERRIDE_FIND_PACKAGE
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)

imcodec_source(libdeflate
  URL https://github.com/ebiggers/libdeflate/releases/download/v1.26/libdeflate-1.26.tar.gz
  URL_HASH SHA256=125856d4656e0feab660f94842f835923410c9281fedbcee64598c918da42b5a
  OVERRIDE_FIND_PACKAGE
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)

imcodec_source(qoi
  URL https://github.com/phoboslab/qoi/archive/97bacc86a9c4abf5a2d452102dc26546c4c670b9.tar.gz
  URL_HASH SHA256=32704988b24321c91114418e884a3fb61a7d0d0004f3ed07a91e73058022bc3b
  SOURCE_SUBDIR __imcodec_download_only
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
