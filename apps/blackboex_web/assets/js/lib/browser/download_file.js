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

export function installDownloadFileHandler(target = window, opts = {}) {
  const handler = (event) => downloadFileFromEvent(event, opts);
  target.addEventListener("phx:download_file", handler);
  target.addEventListener("download_file", handler);
  return () => {
    target.removeEventListener("phx:download_file", handler);
    target.removeEventListener("download_file", handler);
  };
}
