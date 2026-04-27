import component
import config
import djot
import filepath
import frontmatter
import git
import gleam/dict
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/string
import gleam/time/calendar
import glimra
import glimra/theme
import lustre/attribute
import lustre/element
import lustre/element/html
import route
import simplifile
import tom

pub type Image {
  None
  Generated
  File(url: route.Rel)
}

pub type Route {
  Home
  Site(slug: String)
  Article(slug: String)
}

pub type Source {
  Djot(content: String, path: String)
  Elements(
    elements: List(element.Element(Nil)),
    origin_path: option.Option(String),
  )
}

pub type Meta {
  Meta(title: String, description: String, image: Image, author: String)
}

pub type Page {
  Page(published: calendar.Date, route: Route, meta: Meta, src: Source)
}

pub type SitemapItem {
  SitemapItem(url: route.Abs, lastmod: calendar.Date)
}

pub type FeedItem {
  FeedItem(
    id: String,
    title: String,
    description: String,
    url: route.Abs,
    published: calendar.Date,
    updated: calendar.Date,
    html: String,
  )
}

pub fn from_folder(path: String, to_route: fn(String) -> Route) -> List(Page) {
  let assert Ok(files) = simplifile.read_directory(path)
  let files =
    list.filter(files, fn(filename) {
      filename
      |> filepath.join(path, _)
      |> simplifile.is_file()
      |> result.unwrap(False)
    })

  use filename <- list.map(files)

  let assert Ok(content) =
    filename
    |> filepath.join(path, _)
    |> simplifile.read()

  let frontmatter.Extracted(frontmatter:, content:) =
    frontmatter.extract(content)

  let #(published, meta) = extract_meta(frontmatter)
  let src = case filepath.extension(filename) {
    Ok("dj") | Ok("djot") -> Djot(content:, path: filepath.join(path, filename))
    Ok(_) -> panic as "filetype not supported"
    Error(_) -> panic
  }

  let slug = filename |> filepath.base_name |> filepath.strip_extension()
  let route = to_route(slug)

  Page(published:, meta:, src:, route:)
}

fn extract_meta(frontmatter: option.Option(String)) -> #(calendar.Date, Meta) {
  let assert Ok(metadata) = tom.parse(frontmatter |> option.unwrap(""))

  let assert Ok(title) = tom.get_string(metadata, ["title"])
  let assert Ok(description) = tom.get_string(metadata, ["description"])
  let assert Ok(published) = tom.get_date(metadata, ["published"])
  let author =
    tom.get_string(metadata, ["author"]) |> result.unwrap(config.author())

  #(published, Meta(title:, description:, author:, image: Generated))
}

pub fn git_hash(src: Source) -> option.Option(String) {
  case src {
    Djot(content: _, path:) -> git.full_hash(path) |> option.from_result()
    Elements(elements: _, origin_path:) ->
      case origin_path {
        option.Some(path) -> git.full_hash(path) |> option.from_result()
        option.None -> option.None
      }
  }
}

pub fn last_changed_at(src: Source) -> option.Option(calendar.Date) {
  case src {
    Djot(content: _, path:) -> git.last_changed_at(path) |> option.from_result()
    Elements(elements: _, origin_path:) ->
      case origin_path {
        option.Some(path) -> git.last_changed_at(path) |> option.from_result()
        option.None -> option.None
      }
  }
}

pub fn updated_date(page: Page) -> option.Option(calendar.Date) {
  let last_changed_at = last_changed_at(page.src)

  case last_changed_at {
    option.Some(changed) -> {
      case calendar.naive_date_compare(changed, page.published) {
        order.Gt -> last_changed_at
        _ -> option.None
      }
    }
    _ -> option.None
  }
}

pub fn stem(route: Route) -> String {
  case route {
    Home -> "index"
    Site(slug:) -> slug
    Article(slug:) -> "post-" <> slug
  }
}

pub fn rel_path(page: Page) -> route.Rel {
  case page.route {
    Home -> "/"
    Site(slug:) -> "/" <> slug
    Article(slug:) -> "/posts/" <> slug
  }
  |> route.rel_page
}

pub fn abs_path(page: Page) -> route.Abs {
  page
  |> rel_path()
  |> route.abs()
}

pub fn og_image_url(page: Page) -> option.Option(route.Rel) {
  case page.meta.image {
    None -> option.None
    Generated ->
      { "/images/og-" <> stem(page.route) <> ".png" }
      |> route.rel_file
      |> option.Some()
    File(url:) -> url |> option.Some()
  }
}

pub fn to_sitemap_item(page: Page) -> SitemapItem {
  SitemapItem(
    url: abs_path(page),
    lastmod: updated_date(page) |> option.unwrap(page.published),
  )
}

pub fn to_feed_item(page: Page) -> Result(FeedItem, Nil) {
  case page.route {
    Article(slug:) ->
      Ok(FeedItem(
        id: slug,
        title: page.meta.title,
        description: page.meta.description,
        url: abs_path(page),
        published: page.published,
        updated: updated_date(page) |> option.unwrap(page.published),
        html: page
          |> to_minimal_elements()
          |> element.fragment()
          |> element.to_string(),
      ))
    _ -> Error(Nil)
  }
}

fn common(page: Page) {
  [
    html.h1([], [html.text(page.meta.title)]),
    html.div([attribute.class("text-sm")], [
      html.text("Published on "),
      component.time(page.published),
      {
        case updated_date(page) {
          option.Some(updated) ->
            element.fragment([
              html.text(" · "),
              html.text("updated on "),
              component.time(updated),
            ])
          option.None -> element.fragment([])
        }
      },
      {
        case git_hash(page.src) {
          option.Some(hash) -> {
            let short = string.slice(hash, 0, 8)
            element.fragment([
              html.text(" · "),
              html.a([attribute.href(config.repo() <> "/commit/" <> hash)], [
                html.text(short),
              ]),
            ])
          }
          option.None -> element.fragment([])
        }
      },
    ]),
  ]
}

pub fn to_elements(page: Page) -> List(element.Element(Nil)) {
  common(page)
  |> list.append(render(page.src))
}

pub fn to_minimal_elements(page: Page) -> List(element.Element(Nil)) {
  common(page)
  |> list.append(render_minimal(page.src))
}

fn render(source: Source) -> List(element.Element(Nil)) {
  case source {
    Djot(content:, path: _) -> djot.render(content, styled_renderer())
    Elements(elements:, origin_path: _) -> elements
  }
}

fn render_minimal(source: Source) -> List(element.Element(Nil)) {
  case source {
    Djot(content:, path: _) -> djot.render(content, djot.default_renderer())
    Elements(elements:, origin_path: _) -> elements
  }
}

fn styled_renderer() -> djot.Renderer(element.Element(Nil)) {
  let to_attributes = fn(attrs) {
    use attrs, key, val <- dict.fold(attrs, [])
    [attribute.attribute(key, val), ..attrs]
  }

  djot.Renderer(
    ..djot.default_renderer(),
    codeblock: fn(attrs, language, source) {
      let language = option.unwrap(language, "text")

      html.pre(to_attributes(attrs), [
        glimra.new_syntax_highlighter()
        |> glimra.set_theme(theme.default_theme())
        |> glimra.syntax_highlight(source:, language:)
        |> result.unwrap(
          html.code([attribute.attribute("data-lang", language)], [
            element.text(source),
          ]),
        ),
      ])
    },
    image: fn(destination, attributes, alt) {
      let attributes = to_attributes(attributes)
      case destination {
        option.None -> html.span(attributes, [html.text(alt)])
        option.Some(url) ->
          html.figure([], [
            html.img([attribute.src(url), attribute.alt(alt), ..attributes]),
            html.figcaption([], [html.text(alt)]),
          ])
      }
    },
  )
}
