import component
import config
import envoy
import feed
import gleam/list
import gleam/option
import gleam/result
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp
import helper
import index
import layout
import lustre/element
import output.{Bytes, Output, Text}
import page
import route
import simplifile
import sitemap
import typst

const out_dir: String = "./priv"

const pages_path: String = "./pages"

const post_path: String = "./posts"

const drafts_path: String = "./drafts"

const index_path: String = "./src/index.gleam"

const typst_template_path: String = "./src/template.typ"

pub fn main() -> #(Int, duration.Unit) {
  let start = timestamp.system_time()

  let blog_env = envoy.get("BLOG_ENV") |> result.unwrap("PROD")
  let show_drafts = case blog_env {
    "PROD" | "prod" -> False
    _ -> True
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
    True -> page.from_folder(drafts_path, fn(slug) { route.Article(slug) })
    False -> []
  }

  let posts =
    post_path
    |> page.from_folder(fn(slug) { route.Article(slug) })
    |> list.append(drafts)

  let pages = page.from_folder(pages_path, fn(slug) { route.Standalone(slug) })

  let index =
    page.Page(
      route: route.Home,
      published: calendar.Date(2026, calendar.January, 18),
      src: page.Elements(
        index.view(posts),
        origin_path: option.Some(index_path),
      ),
      meta: page.Meta(
        title: index.title,
        description: index.description,
        image: page.Generated,
        author: config.author(),
      ),
    )

  create_page(page.rel_path(index), layout.root(index))

  list.each(pages, fn(page) {
    create_page(page.rel_path(page), layout.root(page))
  })
  list.each(posts, fn(page) {
    create_page(page.rel_path(page), layout.root(page))
  })

  [index]
  |> list.append(pages)
  |> list.append(posts)
  |> list.map(page.to_sitemap_item)
  |> sitemap.build()
  |> component.to_xml_docstring()
  |> Text()
  |> Output(path: route.target(route.Sitemap), contents: _)
  |> output.write(out_dir, _)

  posts
  |> list.filter_map(page.to_feed_item)
  |> feed.build()
  |> component.to_xml_docstring()
  |> Text()
  |> Output(path: route.target(route.Feed), contents: _)
  |> output.write(out_dir, _)

  let assert Ok(markup) = simplifile.read(typst_template_path)

  [index]
  |> list.append(pages)
  |> list.append(posts)
  |> list.each(create_image(markup, _))

  let end = timestamp.system_time()

  timestamp.difference(start, end) |> duration.approximate() |> echo
}

fn create_page(path: route.Rel, element: element.Element(a)) -> Nil {
  Output(path:, contents: Text(element.to_document_string(element)))
  |> output.write(out_dir, _)
}

fn create_image(markup: String, page: page.Page) -> Nil {
  let assert Ok(png) =
    typst.new(markup)
    |> typst.add_binding("title", page.meta.title)
    |> typst.add_binding("description", page.meta.description)
    |> typst.add_binding(
      "date",
      page.published |> helper.date_to_humanized_string(),
    )
    |> typst.add_binding("domain", config.domain())
    |> typst.render()

  Output(path: route.og_image(page.route), contents: Bytes(png))
  |> output.write(out_dir, _)
}
