import gleam/option.{type Option}

pub type ClassDef {
  ClassDef(
    name: String,
    extends: Option(Extends),
    methods: List(Method),
    should_export: Bool,
    source_file: String,
  )
}

pub type Extends {
  Extends(name: String, from: String)
}

pub type Method {
  Method(name: String, params: List(String), is_async: Bool)
}

pub type FusionConfig {
  FusionConfig(
    classes: List(ClassDef),
    runtime: String,
    entry_point: String,
    port: Int,
    minify: Bool,
    source_map: Bool,
    assets: AssetConfig,
  )
}

pub type AssetConfig {
  AssetConfig(
    /// Public directory served via HTTP (e.g., "public")
    directory: String,
    /// Files to embed in worker bundle (e.g., ["priv/secret.cert"])
    includes: List(String),
  )
}

pub type FusionError {
  ScanError(String)
  ParseError(String)
  BuildError(String)
  CodegenError(String)
  IoError(String)
}
