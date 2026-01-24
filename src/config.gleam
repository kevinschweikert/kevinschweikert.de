import gleam/uri

pub fn domain() {
  "kevinschweikert.de"
}

pub fn root_url() {
  "https://" <> domain()
}

pub fn repo() {
  "https://github.com/kevinschweikert/kevinschweikert.de"
}

pub fn url(segment: String) -> uri.Uri {
  let assert Ok(uri) = uri.parse(root_url() <> segment)
  uri
}

pub fn author() {
  "Kevin Schweikert"
}

pub fn title() {
  author()
}

pub fn description() {
  "Hi! I'm Kevin Schweikert, a software engineer with a media technology background and a passion for neapolitan pizza 🍕"
}
