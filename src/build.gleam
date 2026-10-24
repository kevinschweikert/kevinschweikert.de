import config
import content
import envoy
import filepath
import generate/assets
import generate/feed
import generate/og_image
import generate/pages
import generate/sitemap
import git
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import gleam/uri
import home
import output
import route
import simplifile
import site

const out_dir: String = "./priv"

const assets_path = "./assets"

const pages_path: String = "./pages"

const post_path: String = "./posts"

const drafts_path: String = "./drafts"

const home_path: String = "./src/home.gleam"

const typst_template_path: String = "./src/template.typ"

fn paths(site: site.Site) -> List(route.Rel) {
  [route.Feed, route.Sitemap]
  |> list.append({
    use page <- list.flat_map(site.pages)
    [route.Document(page.route), route.OgImage(page.route)]
  })
  |> list.map(route.target)
  |> list.append(list.map(site.assets, site.asset_rel))
}

fn files(dir: String) -> List(site.Asset) {
  let assert Ok(files) = simplifile.get_files(dir)
  use file <- list.map(files)
  site.Asset(source: file, path: string.remove_prefix(file, dir))
}

fn read_pages(
  dir: String,
  to_route: fn(String) -> route.Route,
) -> List(site.Page) {
  let files = case simplifile.read_directory(dir) {
    Ok(files) -> files
    Error(simplifile.Enoent) -> []
    Error(_) -> panic
  }
  use path <- list.filter_map(files)
  let path = filepath.join(dir, path)
  use text <- result.map(simplifile.read(path))
  site.parse(
    path,
    text,
    content.Source(path:, revision: git.revision(path) |> option.from_result()),
    to_route,
  )
}

pub fn main() -> #(Int, duration.Unit) {
  let start = timestamp.system_time()

  let blog_env = envoy.get("BLOG_ENV") |> result.unwrap("PROD")
  let show_drafts = case blog_env {
    "PROD" | "prod" -> False
    _ -> True
  }

  let config = case envoy.get("SITE_URL") {
    Ok(url) -> {
      let assert Ok(base) = uri.parse(url)
      config.Config(..config.default(), base:)
    }
    Error(_) -> config.default()
  }

  case simplifile.is_directory(out_dir) {
    Ok(True) -> {
      let assert Ok(Nil) = simplifile.delete(out_dir)
      Nil
    }
    Ok(False) -> Nil
    Error(_) -> panic
  }

  let drafts = case show_drafts {
    True -> read_pages(drafts_path, route.Article)
    False -> []
  }
  let articles = post_path |> read_pages(route.Article)
  let standalones = pages_path |> read_pages(route.Standalone)

  let home =
    site.Page(
      route: route.Home,
      published: calendar.Date(2026, calendar.January, 18),
      source: option.Some(content.Source(
        path: home_path,
        revision: git.revision(home_path) |> option.from_result(),
      )),
      body: site.Computed(home.view),
      meta: site.Meta(title: config.title, description: config.description),
    )
  let assert Ok(template) = simplifile.read(typst_template_path)

  let pages = [[home], drafts, articles, standalones] |> list.flatten()
  let assets = files(assets_path)
  let site = site.Site(config:, pages:, assets:)
  let paths = paths(site)

  [
    pages.generate,
    assets.generate,
    sitemap.generate,
    feed.generate,
    og_image.generate(template),
  ]
  |> list.flat_map(fn(generate) { generate(site, paths) })
  |> list.each(fn(output) { output.write(out_dir, output) })

  let end = timestamp.system_time()
  timestamp.difference(start, end) |> duration.approximate() |> echo
}
