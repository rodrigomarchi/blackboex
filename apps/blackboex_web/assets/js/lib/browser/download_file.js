/**
 * @file Browser adapter for LiveView file download events.
 */
/**
 * @typedef {object} DownloadFilePayload
 * @property {string} content
 * @property {string} filename
 *
 * @typedef {CustomEvent<DownloadFilePayload>} DownloadFileEvent
 */
/**
 * Downloads a text file described by a LiveView event detail payload.
 * @param {DownloadFileEvent} event - Event containing file content and filename.
 * @param {{document?: Document, URL?: URL, Blob?: Blob}} [opts={}] - Browser API overrides for tests.
 * @returns {boolean} True when a temporary link was clicked.
 */
export function downloadFileFromEvent(event, opts = {}) {
  const { content, filename } = event.detail || {};
  if (!content || !filename) return false;

  const doc = opts.document || document;
  const urlApi = opts.URL || URL;
  const blobCtor = opts.Blob || Blob;
  const blob = new blobCtor([content], { type: "text/plain;charset=utf-8" });
  const url = urlApi.createObjectURL(blob);
  const link = doc.createElement("a");
  link.href = url;
  link.download = filename;
  doc.body.appendChild(link);
  link.click();
  doc.body.removeChild(link);
  urlApi.revokeObjectURL(url);
  return true;
}

/**
 * Installs handlers for Phoenix-prefixed and plain file download events.
 * @param {Window | EventTarget} [target=window] - Event target receiving download events.
 * @param {object} [opts={}] - Adapter overrides forwarded to `downloadFileFromEvent`.
 * @returns {() => void} Cleanup function that removes both listeners.
 */
export function installDownloadFileHandler(target = window, opts = {}) {
  const handler = (event) => downloadFileFromEvent(event, opts);
  target.addEventListener("phx:download_file", handler);
  target.addEventListener("download_file", handler);
  return () => {
    target.removeEventListener("phx:download_file", handler);
    target.removeEventListener("download_file", handler);
  };
}
