/**
 * @file Shared JavaScript library helpers for browser behavior.
 */
/**
 * @typedef {object} DownloadFilePayload
 * @property {string} content
 * @property {string} filename
 *
 * @typedef {CustomEvent<DownloadFilePayload>} DownloadFileEvent
 */
/**
 * Provides download file from event.
 * @param {DownloadFileEvent} event - Browser or library event payload.
 * @param {unknown} opts - Optional configuration values.
 * @returns {unknown} Function result.
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
 * Provides install download file handler.
 * @param {unknown} target - Target event source or DOM element.
 * @param {unknown} opts - Optional configuration values.
 * @returns {unknown} Function result.
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
