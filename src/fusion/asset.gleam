/// Asset reading for embedded and filesystem assets.
///
/// This module provides a unified API for reading assets that works across
/// all runtimes:
/// - On Node/Bun/Deno: reads from filesystem
/// - On Cloudflare Workers: reads from embedded bundle (assets.mjs)
///
/// # Usage
///
/// ```gleam
/// // Read as bytes
/// let assert Ok(cert) = fusion.asset.read("priv/secret.cert")
///
/// // Read as string
/// let assert Ok(config) = fusion.asset.read_string("priv/config.json")
/// ```
import gleam/bit_array
import gleam/result

/// Read an asset as BitArray.
///
/// On Node/Bun/Deno, reads from filesystem relative to current directory.
/// On Cloudflare Workers, reads from embedded assets.mjs.
pub fn read(path: String) -> Result(BitArray, String) {
  do_read_asset(path)
}

/// Read an asset as String.
///
/// Convenience function that reads and converts to string.
pub fn read_string(path: String) -> Result(String, String) {
  use bytes <- result.try(read(path))
  bit_array.to_string(bytes)
  |> result.map_error(fn(_) { "Failed to decode asset as string" })
}

// FFI declarations

@external(erlang, "asset_ffi", "read_asset")
@external(javascript, "./asset_ffi.mjs", "readAsset")
fn do_read_asset(path: String) -> Result(BitArray, String)
