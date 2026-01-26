import gleam/uri

pub fn domain() -> String {
  "kevinschweikert.de"
}

pub fn root_url() -> uri.Uri {
  let assert Ok(root) = uri.parse("https://" <> domain())
  root
}

pub fn repo() -> String {
  "https://github.com/kevinschweikert/kevinschweikert.de"
}

pub fn author() -> String {
  "Kevin Schweikert"
}
