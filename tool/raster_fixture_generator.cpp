// Original synthetic fixtures authored through upstream JPEG and OpenEXR APIs.
#include <cstdio>
#include <jpeglib.h>
#include <ImfChannelList.h>
#include <ImfFrameBuffer.h>
#include <ImfHeader.h>
#include <ImfOutputFile.h>
#include <ImfTiledOutputFile.h>
#include <ImfStandardAttributes.h>
#include <half.h>
#include <string>
#include <vector>

int main(int argc, char** argv) {
  if (argc != 2) return 2;
  const std::string directory(argv[1]);
  for (const int depth : {4, 12, 16}) {
    const std::string path = directory + "/jpeg" + std::to_string(depth) + ".jpg";
    FILE* output = std::fopen(path.c_str(), "wb");
    if (!output) return 1;
    jpeg_compress_struct codec{};
    jpeg_error_mgr error{};
    codec.err = jpeg_std_error(&error);
    jpeg_create_compress(&codec);
    jpeg_stdio_dest(&codec, output);
    codec.image_width = 2;
    codec.image_height = 1;
    codec.input_components = 3;
    codec.in_color_space = JCS_RGB;
    jpeg_set_defaults(&codec);
    jpeg_set_colorspace(&codec, JCS_RGB);
    codec.data_precision = depth;
    jpeg_enable_lossless(&codec, 1, 0);
    jpeg_start_compress(&codec, TRUE);
    const unsigned maximum = (1u << depth) - 1;
    if (depth < 8) {
      JSAMPLE samples[] = {0, 1, 7, 15, 8, 3};
      JSAMPROW row = samples;
      jpeg_write_scanlines(&codec, &row, 1);
    } else if (depth == 12) {
      J12SAMPLE samples[] = {0, 1, 1234, static_cast<J12SAMPLE>(maximum), 2048, 3012};
      J12SAMPROW row = samples;
      jpeg12_write_scanlines(&codec, &row, 1);
    } else {
      J16SAMPLE samples[] = {0, 1, 12345, static_cast<J16SAMPLE>(maximum), 32768, 45678};
      J16SAMPROW row = samples;
      jpeg16_write_scanlines(&codec, &row, 1);
    }
    jpeg_finish_compress(&codec);
    jpeg_destroy_compress(&codec);
    std::fclose(output);
  }
  namespace exr = OPENEXR_IMF_NAMESPACE;
  namespace math = IMATH_NAMESPACE;
  for (const bool tiled : {false, true}) {
    const math::Box2i window(math::V2i(-7, 3), math::V2i(-6, 3));
    exr::Header header(window, window);
    header.compression() = exr::PIZ_COMPRESSION;
    exr::addChromaticities(header, exr::Chromaticities());
    const char* names[] = {"beauty.R", "beauty.G", "beauty.B", "beauty.A"};
    for (const char* name : names) header.channels().insert(name, exr::Channel(exr::FLOAT));
    float samples[] = {1.5f, -0.25f, 0.5f, 1, 0.125f, 0.25f, 0.75f, 0.5f};
    exr::FrameBuffer frame;
    for (int c = 0; c < 4; ++c) frame.insert(names[c], exr::Slice::Make(exr::FLOAT, samples + c, window, 16, 32));
    if (tiled) {
      header.setTileDescription(exr::TileDescription(16, 16));
      exr::TiledOutputFile image((directory + "/exrTiled.exr").c_str(), header, 0);
      image.setFrameBuffer(frame);
      image.writeTiles(0, image.numXTiles() - 1, 0, image.numYTiles() - 1);
    } else {
      exr::OutputFile image((directory + "/exrFloatOffset.exr").c_str(), header, 0);
      image.setFrameBuffer(frame);
      image.writePixels(1);
    }
  }
  exr::Header header(2, 1);
  header.channels().insert("Y", exr::Channel(exr::HALF));
  math::half luminance[] = {0.25f, 1.5f};
  exr::FrameBuffer frame;
  frame.insert("Y", exr::Slice(exr::HALF, reinterpret_cast<char*>(luminance), 2, 4));
  exr::OutputFile image((directory + "/exrLuminance.exr").c_str(), header, 0);
  image.setFrameBuffer(frame);
  image.writePixels(1);
}
