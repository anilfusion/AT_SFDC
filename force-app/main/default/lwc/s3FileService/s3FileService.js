/**
 * Browser-side helpers shared by the amazonS3* components.
 *
 * These only ever work with short-lived presigned URLs issued by S3FilesHelper (Apex);
 * no AWS credentials exist in the browser.
 */

const CRC32_TABLE = (() => {
    const table = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) {
            c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        }
        table[n] = c >>> 0;
    }
    return table;
})();

const CHECKSUM_CHUNK_BYTES = 8 * 1024 * 1024;

/**
 * Computes the CRC32 of a file, base64-encoded big-endian, as S3 expects in the
 * x-amz-checksum-crc32 header. Reads the file in 8 MB chunks so multi-GB files never
 * have to be held in memory.
 *
 * @param {File} file
 * @param {(percent: number) => void} [onProgress]
 * @returns {Promise<string>}
 */
export async function crc32Base64(file, onProgress) {
    let crc = 0xffffffff;
    for (let offset = 0; offset < file.size; offset += CHECKSUM_CHUNK_BYTES) {
        // eslint-disable-next-line no-await-in-loop
        const bytes = new Uint8Array(await file.slice(offset, offset + CHECKSUM_CHUNK_BYTES).arrayBuffer());
        for (let i = 0; i < bytes.length; i++) {
            crc = CRC32_TABLE[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
        }
        if (onProgress) {
            onProgress(Math.round((Math.min(offset + CHECKSUM_CHUNK_BYTES, file.size) / file.size) * 100));
        }
    }
    crc = (crc ^ 0xffffffff) >>> 0;
    return btoa(String.fromCharCode((crc >>> 24) & 0xff, (crc >>> 16) & 0xff, (crc >>> 8) & 0xff, crc & 0xff));
}

/**
 * PUTs a file to a presigned S3 URL. XMLHttpRequest (not fetch) is used so upload progress
 * can be reported. Resolves with the object's ETag, which requires ETag in the bucket's
 * CORS ExposeHeaders (otherwise it resolves with null).
 *
 * @param {string} url presigned PUT URL
 * @param {File} file
 * @param {(percent: number) => void} [onProgress]
 * @param {Object<string,string>} [headers] signed headers returned by getUploadUrl; must be sent as-is
 * @returns {Promise<string|null>}
 */
export function putToS3(url, file, onProgress, headers) {
    return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open('PUT', url);
        xhr.setRequestHeader('Content-Type', file.type || 'application/octet-stream');
        Object.entries(headers || {}).forEach(([name, value]) => xhr.setRequestHeader(name, value));
        xhr.upload.onprogress = (e) => {
            if (onProgress && e.lengthComputable) {
                onProgress(Math.max(1, Math.round((e.loaded / e.total) * 100)));
            }
        };
        xhr.onload = () => {
            if (xhr.status >= 200 && xhr.status < 300) {
                resolve(xhr.getResponseHeader('ETag'));
            } else {
                reject(new Error(`S3 upload failed (${xhr.status}): ${xhr.responseText}`));
            }
        };
        xhr.onerror = () => reject(new Error('Network error during upload. Check the bucket CORS configuration.'));
        xhr.send(file);
    });
}

/** Starts a browser download of a presigned URL (Content-Disposition: attachment is signed into it). */
export function triggerDownload(url) {
    const link = document.createElement('a');
    link.href = url;
    link.rel = 'noopener';
    document.body.appendChild(link);
    link.click();
    link.remove();
}

/**
 * Opens a new tab synchronously (so popup blockers allow it) and points it at the URL
 * once the async getter resolves. Closes the tab if the getter fails.
 *
 * @param {() => Promise<string>} getUrl
 */
export async function openInNewTab(getUrl) {
    const win = window.open('', '_blank');
    try {
        const url = await getUrl();
        if (win) {
            win.location.href = url;
        } else {
            window.open(url, '_blank');
        }
    } catch (error) {
        if (win) {
            win.close();
        }
        throw error;
    }
}

/** Maps S3FilesHelper.S3File results to the row shape the file-table templates use. */
export function toFileRows(files, fileTypesMap) {
    return (files || []).map((item) => {
        const ext = item.name.substring(item.name.lastIndexOf('.') + 1).toLowerCase();
        return {
            Key: item.key,
            name: item.name,
            Size: item.size,
            LastModified: item.lastModified,
            type: `doctype:${fileTypesMap(ext) || 'unknown'}`
        };
    });
}

/** Extracts a readable message from an Apex (AuraHandledException) or JS error. */
export function errorMessage(error) {
    return error?.body?.message || error?.message || 'Unknown error';
}