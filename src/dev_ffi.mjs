// Dev FFI for JavaScript target

export function encodeBase64(data) {
  // data is a BitArray (Uint8Array) in JavaScript
  if (data instanceof Uint8Array) {
    let binary = '';
    for (let i = 0; i < data.length; i++) {
      binary += String.fromCharCode(data[i]);
    }
    return btoa(binary);
  }
  // Fallback for other types
  return btoa(String.fromCharCode(...new Uint8Array(data)));
}
