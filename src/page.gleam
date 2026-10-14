import component
import config.{type Config}
import djot
import filepath
import frontmatter
import git
import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/uri
import glimra
import glimra/theme
import lustre/attribute
import lustre/element
import lustre/element/html
import route.{type Route}
import simplifile
import tom

pub type Revision {
  Revision(hash: String, changed_at: calendar.Date)
}

pub type Image {
  None
  Generated
  File(url: route.Rel)
}

pub type Body {
  Djot(content: String)
  Elements(elements: List(element.Element(Nil)))
}

pub type Source {
  Source(path: String, revision: option.Option(Revision))
}

pub type Meta {
  Meta(title: String, description: String, image: Image)
}

pub type Page {
  Page(
    published: calendar.Date,
    route: Route,
    meta: Meta,
    body: Body,
    source: option.Option(Source),
  )
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
  let files = case simplifile.read_directory(path) {
    Ok(files) -> files
    Error(simplifile.Enoent) -> []
    Error(_) -> panic
  }
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
  let full_path = filepath.join(path, filename)
  let source = source(full_path)
  let body = case filepath.extension(filename) {
    Ok("dj") | Ok("djot") -> Djot(content:)
    Ok(_) -> panic as "filetype not supported"
    Error(_) -> panic
  }

  let slug = filename |> filepath.base_name |> filepath.strip_extension()
  let route = to_route(slug)

  Page(published:, meta:, body:, source:, route:)
}

pub fn source(path: String) -> option.Option(Source) {
  option.Some(Source(path: path, revision: revision(path)))
}

fn revision(path: String) -> option.Option(Revision) {
  {
    use hash <- result.try(git.full_hash(path))
    use changed_at <- result.map(git.last_changed_at(path))
    Revision(hash:, changed_at:)
  }
  |> option.from_result()
}

fn extract_meta(frontmatter: option.Option(String)) -> #(calendar.Date, Meta) {
  let assert Ok(metadata) = tom.parse(frontmatter |> option.unwrap(""))

  let assert Ok(title) = tom.get_string(metadata, ["title"])
  let assert Ok(description) = tom.get_string(metadata, ["description"])
  let assert Ok(published) = tom.get_date(metadata, ["published"])

  #(published, Meta(title:, description:, image: Generated))
}

pub fn updated_date(page: Page) -> option.Option(calendar.Date) {
  case page.source {
    option.Some(src) -> {
      case src.revision {
        option.Some(Revision(changed_at:, ..)) -> option.Some(changed_at)
        option.None -> option.None
      }
    }
    option.None -> option.None
  }
}

pub fn rel_path(page: Page) -> route.Rel {
  route.of(page.route)
}

pub fn abs_path(page: Page, base: uri.Uri) -> route.Abs {
  page
  |> rel_path()
  |> route.abs(on: base)
}

pub fn to_sitemap_item(page: Page, config: config.Config) -> SitemapItem {
  SitemapItem(
    url: abs_path(page, config.base),
    lastmod: updated_date(page) |> option.unwrap(page.published),
  )
}

pub fn to_feed_item(page: Page, config: Config) -> Result(FeedItem, Nil) {
  case page.route {
    route.Article(slug:) ->
      Ok(FeedItem(
        id: slug,
        title: page.meta.title,
        description: page.meta.description,
        url: abs_path(page, config.base),
        published: page.published,
        updated: updated_date(page) |> option.unwrap(page.published),
        html: page
          |> to_minimal_elements(config)
          |> element.fragment()
          |> element.to_string(),
      ))
    _ -> Error(Nil)
  }
}

fn common(page: Page, config: Config) {
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
        case page.source {
          option.Some(src) -> {
            case src.revision {
              option.Some(Revision(hash:, ..)) -> {
                let short = string.slice(hash, 0, 8)
                element.fragment([
                  html.text(" · "),
                  html.a([attribute.href(config.commit_url(config, hash))], [
                    html.text(short),
                  ]),
                ])
              }
              option.None -> element.fragment([])
            }
          }
          option.None -> element.fragment([])
        }
      },
    ]),
  ]
}

pub fn to_elements(page: Page, config: Config) -> List(element.Element(Nil)) {
  common(page, config)
  |> list.append(render(page.body))
}

pub fn to_minimal_elements(
  page: Page,
  config: Config,
) -> List(element.Element(Nil)) {
  common(page, config)
  |> list.append(render_minimal(page.body))
}

fn render(body: Body) -> List(element.Element(Nil)) {
  case body {
    Djot(content:) -> djot.render(content, styled_renderer())
    Elements(elements:) -> elements
  }
}

fn render_minimal(body: Body) -> List(element.Element(Nil)) {
  case body {
    Djot(content:) -> djot.render(content, djot.default_renderer())
    Elements(elements:) -> elements
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
