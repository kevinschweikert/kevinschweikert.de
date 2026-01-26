import config
import filepath
import gleam/option
import gleam/string
import gleam/uri

type Kind {
  File
  Page
}

pub opaque type Abs {
  Abs(uri.Uri, Kind)
}

pub opaque type Rel {
  Rel(uri.Uri, Kind)
}

pub fn abs(rel: Rel) -> Abs {
  let Rel(u, kind) = rel
  let assert Ok(u) = config.root_url() |> uri.merge(u)
  Abs(u, kind)
}

pub fn abs_from_base(base: Abs, path: Rel) {
  let Abs(a, _) = base
  let Rel(b, kind) = path
  let assert Ok(u) = uri.merge(a, b)
  Abs(u, kind)
}

/// Creates a new relative string to root-site relative. Has to start with /
/// 
pub fn rel_page(path: String) -> Rel {
  let assert True = string.starts_with(path, "/")
  let assert Ok(uri) = uri.parse(path)
  let assert option.None = uri.scheme
  let assert option.None = uri.host
  Rel(uri, Page)
}

pub fn rel_file(path: String) -> Rel {
  let assert True = string.starts_with(path, "/")
  let assert Ok(uri) = uri.parse(path)
  let assert option.None = uri.scheme
  let assert option.None = uri.host
  Rel(uri, File)
}

pub fn rel_string(rel: Rel) -> String {
  let Rel(uri, kind) = rel

  uri.path
  |> canonicalize(kind)
}

pub fn abs_string(abs: Abs) -> String {
  let Abs(uri, kind) = abs
  let canonicalized_path = uri.path |> canonicalize(kind)
  let canonicalized_uri = uri.Uri(..uri, path: canonicalized_path)
  uri.to_string(canonicalized_uri)
}

fn canonicalize(string: String, kind: Kind) -> String {
  case kind, string, string.ends_with(string, "/") {
    Page, "", _ -> "/"
    Page, _, True -> string
    Page, _, False -> string <> "/"
    File, _, _ -> string
  }
}

pub fn fs_rel_path(rel: Rel) -> String {
  let Rel(uri, kind) = rel

  uri.path
  |> strip_leading_slash()
  |> maybe_add_extension(kind)
}

pub fn fs_abs_path(abs: Abs) -> String {
  let Abs(uri, kind) = abs

  uri.path
  |> strip_leading_slash()
  |> maybe_add_extension(kind)
}

fn strip_leading_slash(string: String) -> String {
  case string {
    "/" <> rest -> rest
    rest -> rest
  }
}

fn maybe_add_extension(string: String, kind: Kind) {
  case kind {
    Page -> filepath.join(string, "/index.html")
    File -> string
  }
}
