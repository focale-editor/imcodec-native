// One Worker reuses one module. Its synchronous operations naturally serialize
// concurrent messages without blocking the browser's main thread.
let modulePromise;
const loadModule = () => modulePromise ??= import('./imcodec_native.mjs')
  .then(({default: createModule}) => createModule());

// Output buffers are copied out of Wasm before native allocations are released.
self.onmessage = async ({data: request}) => {
  let module;
  let input = 0;
  let result = 0;
  try {
    module = await loadModule();
    const bytes = new Uint8Array(request.bytes);
    input = module._malloc(Math.max(1, bytes.length));
    if (!input) throw new Error('Could not allocate WebAssembly input memory');
    module.HEAPU8.set(bytes, input);
    if (request.operation === 0) {
      result = module._imcodec_decode(input, bytes.length, request.format,
        request.maxPixels, request.maxDecodedBytes, request.preserveDepth ? 1 : 0,
        request.maxIccProfileBytes);
    } else if (request.operation === 1) {
      result = module._imcodec_inspect(input, bytes.length, request.format,
        request.maxIccProfileBytes, request.maxMetadataBytes);
    } else if (request.operation === 2) {
      result = module._imcodec_encode(input, bytes.length, request.width,
        request.height, request.format, request.quality, request.lossless ? 1 : 0,
        request.speed, request.maxOutputBytes);
    } else {
      throw new Error('Unsupported codec operation');
    }
    const error = module.UTF8ToString(module._imcodec_result_error(result));
    if (error) throw new Error(error);
    const buffers = [0, 1, 2, 3].map(field => {
      const size = module._imcodec_result_number(result, field + 4);
      if (!size) return null;
      const start = module._imcodec_result_data(result, field);
      return module.HEAPU8.slice(start, start + size).buffer;
    });
    self.postMessage({
      id: request.id,
      width: module._imcodec_result_number(result, 0),
      height: module._imcodec_result_number(result, 1),
      depth: module._imcodec_result_number(result, 2),
      sourceDepth: module._imcodec_result_number(result, 3),
      bytes: buffers[0], iccProfile: buffers[1],
      exifMetadata: buffers[2], xmpMetadata: buffers[3],
    }, buffers.filter(Boolean));
  } catch (error) {
    self.postMessage({
      id: request.id,
      error: error instanceof Error ? error.message : String(error),
    });
  } finally {
    if (module) {
      module._imcodec_result_free(result);
      module._free(input);
    }
  }
};
