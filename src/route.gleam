import config
import gleam/option
import gleam/string
import gleam/uri

pub opaque type Abs {
  Abs(uri.Uri)
}

pub opaque type Rel {
  Rel(uri.Uri)
}

pub fn base() -> Abs {
  abs_from_string(config.root_url())
}

pub fn abs(path: Rel) -> Abs {
  abs_from_base(base(), path)
}

pub fn abs_from_base(base: Abs, path: Rel) {
  let Abs(a) = base
  let Rel(b) = path
  let assert Ok(u) = uri.merge(a, b)
  Abs(u)
}

/// Creates a new relative string to root-site relative. Has to start with /
/// 
pub fn rel_from_string(path: String) -> Rel {
  let assert True = string.starts_with(path, "/")
  let assert Ok(uri) = uri.parse(path)
  let assert option.None = uri.scheme
  let assert option.None = uri.host
  Rel(uri)
}

pub fn abs_from_string(path: String) -> Abs {
  let assert Ok(uri) = uri.parse(path)
  let assert option.Some(_) = uri.scheme
  let assert option.Some(_) = uri.host
  Abs(uri)
}

pub fn rel_uri(rel: Rel) -> uri.Uri {
  let Rel(u) = rel
  u
}

pub fn abs_uri(abs: Abs) -> uri.Uri {
  let Abs(u) = abs
  u
}

pub fn rel_string(rel: Rel) -> String {
  rel |> rel_uri() |> uri.to_string()
}

pub fn abs_string(abs: Abs) -> String {
  abs |> abs_uri() |> uri.to_string()
}

pub fn fs_rel_path(rel: Rel) -> String {
  let Rel(uri) = rel
  case uri.path {
    "/" <> rest -> rest
    path -> path
  }
}

pub fn fs_abs_path(abs: Abs) -> String {
  let Abs(uri) = abs
  case uri.path {
    "/" <> rest -> rest
    path -> path
  }
}
