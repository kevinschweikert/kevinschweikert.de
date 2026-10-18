import component
import config.{type Config}
import content.{Revision}
import djot/html as djot_html
import djot/render
import filepath
import frontmatter
import gleam/dict
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/uri
import glimra
import jot
import lustre/attribute
import lustre/element
import lustre/element/html
import route.{type Route}
import tom

pub type Site {
  Site(config: config.Config, pages: List(Page), assets: List(Asset))
}

pub type Page {
  Page(
    published: calendar.Date,
    route: Route,
    meta: Meta,
    body: Body,
    source: option.Option(content.Source),
  )
}

pub type Asset {
  Asset(source: String, path: String)
}

pub type Body {
  Djot(jot.Document)
  Computed(fn(Site) -> List(element.Element(Nil)))
}

pub type Meta {
  Meta(title: String, description: String)
}

pub fn parse(
  path: String,
  text: String,
  source: content.Source,
  to_route: fn(String) -> Route,
) -> Page {
  let frontmatter.Extracted(frontmatter:, content:) = frontmatter.extract(text)

  let #(published, meta) = extract_meta(frontmatter)
  let body = case filepath.extension(path) {
    Ok("dj") | Ok("djot") -> Djot(jot.parse(content))
    Ok(_) -> panic as "filetype not supported"
    Error(_) -> panic
  }

  let slug = path |> filepath.base_name |> filepath.strip_extension()
  let route = to_route(slug)

  Page(published:, meta:, body:, source: option.Some(source), route:)
}

fn extract_meta(frontmatter: option.Option(String)) -> #(calendar.Date, Meta) {
  let assert Ok(metadata) = tom.parse(frontmatter |> option.unwrap(""))
  let assert Ok(title) = tom.get_string(metadata, ["title"])
  let assert Ok(description) = tom.get_string(metadata, ["description"])
  let assert Ok(published) = tom.get_date(metadata, ["published"])

  #(published, Meta(title:, description:))
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

pub fn asset_rel(asset: Asset) -> route.Rel {
  route.asset(asset.path)
}

pub fn abs_path(page: Page, base: uri.Uri) -> route.Abs {
  page
  |> rel_path()
  |> route.abs(on: base)
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

pub fn to_elements(page: Page, site: Site) -> List(element.Element(Nil)) {
  common(page, site.config)
  |> list.append(render(page, site))
}

pub fn to_minimal_elements(
  page: Page,
  site: Site,
) -> List(element.Element(Nil)) {
  common(page, site.config)
  |> list.append(render_minimal(page, site))
}

fn render(page: Page, site: Site) -> List(element.Element(Nil)) {
  case page.body {
    Djot(document) -> render.render(document, browser())
    Computed(view) -> view(site)
  }
}

fn render_minimal(page: Page, site: Site) -> List(element.Element(Nil)) {
  let page_uri =
    route.of(page.route) |> route.abs(on: site.config.base) |> route.abs_uri()
  case page.body {
    Djot(document) -> render.render(document, feed(page_uri))
    Computed(view) -> view(site)
  }
}

fn browser() -> render.Renderer {
  render.Renderer(
    container: fn(node, ctx) {
      case node {
        render.Codeblock(attributes:, language:, content:) ->
          highlight(attributes, language, content)
        _ -> djot_html.container(node, ctx)
      }
    },
    inline: fn(node, ctx) {
      case node {
        render.Image(attributes:, content:, url:) ->
          figure(attributes, content, url)
        _ -> djot_html.inline(node, ctx)
      }
    },
  )
}

fn feed(page: uri.Uri) -> render.Renderer {
  render.Renderer(container: djot_html.container, inline: fn(node, ctx) {
    node
    |> absolutize(page)
    |> djot_html.inline(ctx)
  })
}

fn absolutize(node: render.Inline, page: uri.Uri) -> render.Inline {
  case node {
    render.Link(attributes:, content:, url:) -> {
      let absolute = url |> absolute(page)
      render.Link(attributes:, content:, url: absolute)
    }
    render.Image(attributes:, content:, url:) -> {
      let absolute = url |> absolute(page)
      render.Image(attributes:, content:, url: absolute)
    }
    _ -> node
  }
}

// uri.merge discards a trailing slash but our canonical representation wants it
fn absolute(url: String, page: uri.Uri) -> String {
  {
    use parsed <- result.try(uri.parse(url))
    use merged <- result.try(uri.merge(page, parsed))
    let path = case
      string.ends_with(parsed.path, "/") && !string.ends_with(merged.path, "/")
    {
      True -> merged.path <> "/"
      _ -> merged.path
    }

    Ok(uri.to_string(uri.Uri(..merged, path:)))
  }
  |> result.unwrap(url)
}

fn figure(
  attributes: dict.Dict(String, String),
  content: List(render.Inline),
  url: String,
) -> element.Element(Nil) {
  let alt = djot_html.text_content(content)
  let attributes = djot_html.to_attributes(attributes)
  html.figure([], [
    html.img([attribute.src(url), attribute.alt(alt), ..attributes]),
    html.figcaption([], [html.text(alt)]),
  ])
}

fn highlight(
  attributes: dict.Dict(String, String),
  language: String,
  source: String,
) -> element.Element(Nil) {
  html.pre(djot_html.to_attributes(attributes), [
    case
      glimra.new_syntax_highlighter()
      |> glimra.syntax_highlight(source:, language:)
    {
      Ok(element) -> element
      Error(err) ->
        case err {
          glimra.UnsupportedLanguage(language:) -> {
            io.println_error("language " <> language <> " not supported")
            html.code([attribute.attribute("data-lang", language)], {
              let lines = source |> string.trim |> string.split("\n")
              use line <- list.map(lines)
              html.span([attribute.class("line")], [html.text(line)])
            })
          }
          glimra.TreeSitterError -> panic
          glimra.UnmatchedHighlightEvents -> panic
        }
    },
  ])
}
