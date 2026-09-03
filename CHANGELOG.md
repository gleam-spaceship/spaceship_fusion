# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-12-XX

### Added

- Class scanning and metadata parsing from `.gleam` files
- ES6 class code generation from Gleam modules
- Platform-specific shim generation (Cloudflare Workers, Node.js, Bun, Deno)
- `glint`-based CLI with commands: `init`, `build`, `scan`, `class create`, `class list`, `dev`
- Dynamic Cloudflare `compatibility_date` generation
- `fusion init` with interactive project setup and wrangler.toml generation
- `fusion build` for compiling and bundling with esbuild
- `fusion dev` for local development with hot reload
- Asset embedding and static file support (`[fusion.assets]` config)
- Runtime-specific adapter copying for Cloudflare, Node.js, Bun, and Deno
- Source map support for production debugging
