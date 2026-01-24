import component
import config
import envoy
import feed
import filepath
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
import page
import route
import simplifile
import sitemap
import typst

const out_dir = "./priv"

const pages_path = "./src/pages"

const post_path = "./src/pages/posts"

const index_path = "./src/index.gleam"

const typst_template_path = "./src/template.typ"

pub fn main() {
  let start = timestamp.system_time()

  let blog_env = envoy.get("BLOG_ENV") |> result.unwrap("PROD")
  let show_draft = case blog_env {
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

  let posts =
    post_path
    |> page.from_folder(fn(slug) { page.Article(slug) })
    |> list.filter(fn(page) { page.is_published(page) || show_draft })

  let pages =
    pages_path
    |> page.from_folder(fn(slug) { page.Site(slug) })
    |> list.filter(fn(page) { page.is_published(page) || show_draft })

  let index =
    page.Page(
      route: page.Home,
      status: page.Published(calendar.Date(
        2026,
        calendar.month_from_int(1) |> result.lazy_unwrap(fn() { panic }),
        18,
      )),
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
  |> list.filter_map(page.to_sitemap_item)
  |> sitemap.build()
  |> component.to_xml_docstring()
  |> write_file(filepath.join(out_dir, "sitemap.xml"), _)

  posts
  |> list.filter_map(page.to_feed_item)
  |> feed.build()
  |> component.to_xml_docstring()
  |> write_file(filepath.join(out_dir, "feed.xml"), _)

  let assert Ok(markup) = simplifile.read(typst_template_path)

  [index]
  |> list.append(pages)
  |> list.append(posts)
  |> list.each(create_image(markup, _))

  let end = timestamp.system_time()

  timestamp.difference(start, end) |> duration.approximate() |> echo
}

fn create_page(path: route.Rel, element: element.Element(a)) -> Nil {
  let path = route.fs_rel_path(path)

  out_dir
  |> filepath.join(path)
  |> write_file(element.to_document_string(element))
}

fn create_image(markup: String, page: page.Page) {
  case page.og_image_url(page) {
    option.Some(rel) -> {
      let assert Ok(png) =
        typst.new(markup)
        |> typst.add_binding("title", page.meta.title)
        |> typst.add_binding("description", page.meta.description)
        |> typst.add_binding(
          "date",
          page.published_date(page.status)
            |> helper.date_to_humanized_string(),
        )
        |> typst.add_binding("domain", config.domain())
        |> typst.render()

      rel
      |> route.fs_rel_path()
      |> filepath.join(out_dir, _)
      |> simplifile.write_bits(png)
    }
    option.None -> Ok(Nil)
  }
}

fn write_file(to path: String, write contents: String) -> Nil {
  let assert Ok(Nil) =
    simplifile.create_directory_all(filepath.directory_name(path))
  let assert Ok(Nil) = simplifile.write(contents, to: path)
  Nil
}
