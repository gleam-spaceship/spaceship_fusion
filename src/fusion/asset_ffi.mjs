// Asset FFI for reading embedded and filesystem assets

// Try to import embedded assets (will fail if not Cloudflare build)
let embeddedAssets = null;
try {
  // This import will only exist if assets.mjs was generated
  const assetsModule = await import('./assets.mjs');
  embeddedAssets = assetsModule;
} catch (e) {
  // No embedded assets available
}

/**
 * Read an asset, trying embedded first then filesystem.
 * @param {string} path - Asset path
 * @returns {Uint8Array} Asset contents
 */
export function readAsset(path) {
  // Try embedded assets first (Cloudflare Workers)
  if (embeddedAssets) {
    try {
      const bytes = embeddedAssets.getAsset(path);
      if (bytes !== null) {
        return bytes;
      }
    } catch (e) {
      // Fall through to filesystem
    }
  }
  
  // Try filesystem (Node/Bun/Deno)
  try {
    const { readFileSync } = await import('node:fs');
    return readFileSync(path);
  } catch (e) {
    throw new Error(`Could not read asset: ${path}`);
  }
}

/**
 * Read a file from the filesystem.
 * @param {string} path - File path relative to current directory
 * @returns {Uint8Array} File contents
 */
export function readFilesystem(path) {
  try {
    const { readFileSync } = require('node:fs');
    return readFileSync(path);
  } catch (e) {
    throw new Error(`Could not read file: ${path}`);
  }
}

/**
 * Get an embedded asset by path.
 * @param {string} path - Asset path
 * @returns {Uint8Array|null} Asset contents or null if not found
 */
export function getEmbedded(path) {
  if (!embeddedAssets) {
    return null;
  }
  
  try {
    // getAsset returns Uint8Array or null
    return embeddedAssets.getAsset(path);
  } catch (e) {
    return null;
  }
}

/**
 * Check if running on Cloudflare Workers.
 * @returns {boolean} True if on Cloudflare Workers
 */
export function isCloudflare() {
  return typeof globalThis !== 'undefined' && 
         typeof globalThis.__env !== 'undefined';
}
