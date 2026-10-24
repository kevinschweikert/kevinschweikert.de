import filepath
import gleam/option
import gleam/string
import gleam/uri

type Kind {
  File
  Page
}

pub type Route {
  Home
  Standalone(slug: String)
  Article(slug: String)
}

pub type Target {
  Document(Route)
  OgImage(Route)
  Feed
  Sitemap
}

pub opaque type Abs {
  Abs(uri.Uri, Kind)
}

pub opaque type Rel {
  Rel(uri.Uri, Kind)
}

pub fn abs(rel: Rel, on base: uri.Uri) -> Abs {
  let Rel(u, kind) = rel
  let assert Ok(u) = uri.merge(base, u)
  Abs(u, kind)
}

pub fn of(route: Route) -> Rel {
  Document(route) |> target()
}

pub fn og_image(route: Route) -> Rel {
  OgImage(route) |> target()
}

pub fn target(target: Target) -> Rel {
  case target {
    Document(route) -> document_path(route)
    OgImage(route) -> og_image_path(route)
    Feed -> rel_file("/feed.xml")
    Sitemap -> rel_file("/sitemap.xml")
  }
}

pub fn asset(path: String) -> Rel {
  rel_file(path)
}

fn document_path(route: Route) -> Rel {
  case route {
    Home -> rel_page("/")
    Standalone(slug:) -> rel_page("/" <> slug)
    Article(slug:) -> rel_page("/posts/" <> slug)
  }
}

fn og_image_path(route: Route) -> Rel {
  let Rel(uri, _) = document_path(route)
  let stem = case uri.path {
    "/" -> "/index"
    path -> path
  }

  rel_file("/images/og" <> stem <> ".png")
}

fn rel_page(path: String) -> Rel {
  let assert True = string.starts_with(path, "/")
  let assert Ok(uri) = uri.parse(path)
  let assert option.None = uri.scheme
  let assert option.None = uri.host
  Rel(uri, Page)
}

fn rel_file(path: String) -> Rel {
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

pub fn abs_uri(abs: Abs) -> uri.Uri {
  let Abs(uri, kind) = abs
  uri.Uri(..uri, path: uri.path |> canonicalize(kind))
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

fn strip_leading_slash(string: String) -> String {
  case string {
    "/" <> rest -> rest
    rest -> rest
  }
}

fn maybe_add_extension(string: String, kind: Kind) -> String {
  case kind {
    Page -> filepath.join(string, "/index.html")
    File -> string
  }
}
