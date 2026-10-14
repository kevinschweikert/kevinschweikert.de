import component
import config
import content
import envoy
import feed
import gleam/list
import gleam/result
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import gleam/uri
import helper
import home
import layout
import lustre/element
import output.{Bytes, Output, Text}
import route
import simplifile
import site
import sitemap
import typst

const out_dir: String = "./priv"

const pages_path: String = "./pages"

const post_path: String = "./posts"

const drafts_path: String = "./drafts"

const home_path: String = "./src/home.gleam"

const typst_template_path: String = "./src/template.typ"

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

  let assert Ok(_) = simplifile.copy_directory("./assets", out_dir)

  let drafts = case show_drafts {
    True -> site.from_folder(drafts_path, route.Article)
    False -> []
  }

  let content_pages =
    post_path
    |> site.from_folder(route.Article)
    |> list.append(drafts)
    |> list.append(site.from_folder(pages_path, route.Standalone))

  let home =
    site.Page(
      route: route.Home,
      published: calendar.Date(2026, calendar.January, 18),
      source: content.source(home_path),
      body: site.Computed(home.view),
      meta: site.Meta(title: config.title, description: config.description),
    )

  let site = site.Site(config:, pages: [home, ..content_pages])

  site.pages
  |> list.map(fn(page) {
    create_page(site.rel_path(page), layout.root(page, site))
  })

  site
  |> sitemap.build()
  |> component.to_xml_docstring()
  |> Text()
  |> Output(path: route.target(route.Sitemap), contents: _)
  |> output.write(out_dir, _)

  site
  |> feed.build()
  |> component.to_xml_docstring()
  |> Text()
  |> Output(path: route.target(route.Feed), contents: _)
  |> output.write(out_dir, _)

  let assert Ok(markup) = simplifile.read(typst_template_path)

  site.pages
  |> list.each(create_image(markup, _, config))

  let end = timestamp.system_time()

  timestamp.difference(start, end) |> duration.approximate() |> echo
}

fn create_page(path: route.Rel, element: element.Element(a)) -> Nil {
  Output(path:, contents: Text(element.to_document_string(element)))
  |> output.write(out_dir, _)
}

fn create_image(markup: String, page: site.Page, config: config.Config) -> Nil {
  let assert Ok(png) =
    typst.new(markup)
    |> typst.add_binding("title", page.meta.title)
    |> typst.add_binding("description", page.meta.description)
    |> typst.add_binding(
      "date",
      page.published |> helper.date_to_humanized_string(),
    )
    |> typst.add_binding("domain", config.domain(config))
    |> typst.render()

  Output(path: route.og_image(page.route), contents: Bytes(png))
  |> output.write(out_dir, _)
}
