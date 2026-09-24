# libheif and libtiff share the pinned standalone libjpeg-turbo build.
set(JPEG_FOUND TRUE)
set(JPEG_VERSION 80)
set(JPEG_INCLUDE_DIRS "${libjpeg_SOURCE_DIR}/src;${libjpeg_BINARY_DIR}")
set(JPEG_LIBRARIES imcodec_jpeg)
