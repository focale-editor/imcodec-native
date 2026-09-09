import createModule from './imcodec_native.mjs';

// The Dart loader inserts this external module script; no inline script or eval
// is required. Emscripten locates the adjacent Wasm using import.meta.url.
globalThis.imcodecNativeCreateModule = () => createModule();
globalThis.imcodecNativeCreateWorker = url => {
  const options = {type: 'module', name: 'ImcodecNative'};
  if (!globalThis.crossOriginIsolated) return new Worker(url, options);

  // A cross-origin-isolated document requires its root Worker response to
  // carry a matching COEP header. Flutter's Wasm test server applies that
  // header only to HTML, so bootstrap from a same-realm blob and import the
  // ordinary external module from there. Production servers with equivalent
  // header behavior benefit from the same fallback.
  const moduleUrl = new URL(url, document.baseURI).href;
  const bootstrapUrl = URL.createObjectURL(new Blob([
    `import ${JSON.stringify(moduleUrl)};`,
  ], {type: 'text/javascript'}));
  const worker = new Worker(bootstrapUrl, options);
  setTimeout(() => URL.revokeObjectURL(bootstrapUrl), 0);
  return worker;
};
globalThis.imcodecNativeWorkerError = event => {
  const location = event.filename
    ? ` (${event.filename}:${event.lineno}:${event.colno})`
    : '';
  return `${event.message || 'Unknown Worker error'}${location}`;
};
