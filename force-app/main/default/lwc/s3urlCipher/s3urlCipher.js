const base64ToBytes = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));

let cachedKey;

/**
 * Decrypts a value produced by Apex Crypto.encryptWithManagedIV('AES256', ...).
 * Layout: [16-byte IV][ciphertext], base64-encoded.
 */
export async function decryptFromApex(cipherB64, keyB64) {
    if (!cachedKey) {
        cachedKey = await crypto.subtle.importKey(
            'raw',
            base64ToBytes(keyB64),
            { name: 'AES-CBC' },
            false,
            ['decrypt']
        );
    }
    const data = base64ToBytes(cipherB64);
    const plain = await crypto.subtle.decrypt(
        { name: 'AES-CBC', iv: data.slice(0, 16) },
        cachedKey,
        data.slice(16)
    );
    return new TextDecoder().decode(plain);
}