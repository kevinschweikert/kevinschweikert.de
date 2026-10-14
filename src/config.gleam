import gleam/option
import gleam/uri

pub type Config {
  Config(
    title: String,
    description: String,
    base: uri.Uri,
    author: String,
    repo: uri.Uri,
  )
}

pub fn default() -> Config {
  let assert Ok(repo) =
    uri.parse("https://github.com/kevinschweikert/kevinschweikert.de")
  let assert Ok(base) = uri.parse("https://kevinschweikert.de")

  Config(
    title: "kevinschweikert.de",
    description: "Hi! I'm Kevin Schweikert, a software engineer with a media technology background and a passion for neapolitan pizza 🍕",
    author: "Kevin Schweikert",
    repo: repo,
    base: base,
  )
}

pub fn domain(config: Config) -> String {
  let assert option.Some(domain) = config.base.host
  domain
}

pub fn commit_url(config: Config, hash: String) -> String {
  uri.Uri(..config.repo, path: config.repo.path <> "/commit/" <> hash)
  |> uri.to_string()
}
