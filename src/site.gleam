import component
import config.{type Config}
import content.{Revision}
import djot
import filepath
import frontmatter
import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/uri
import glimra
import glimra/theme
import jot
import lustre/attribute
import lustre/element
import lustre/element/html
import route.{type Route}
import simplifile
import tom

pub type Site {
  Site(config: config.Config, pages: List(Page))
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

pub type Body {
  Djot(jot.Document)
  Computed(fn(Site) -> List(element.Element(Nil)))
}

pub type Meta {
  Meta(title: String, description: String)
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
  let source = content.source(full_path)
  let body = case filepath.extension(filename) {
    Ok("dj") | Ok("djot") -> Djot(jot.parse(content))
    Ok(_) -> panic as "filetype not supported"
    Error(_) -> panic
  }

  let slug = filename |> filepath.base_name |> filepath.strip_extension()
  let route = to_route(slug)

  Page(published:, meta:, body:, source:, route:)
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
  |> list.append(render(page.body, site))
}

pub fn to_minimal_elements(
  page: Page,
  site: Site,
) -> List(element.Element(Nil)) {
  common(page, site.config)
  |> list.append(render_minimal(page.body, site))
}

fn render(body: Body, site: Site) -> List(element.Element(Nil)) {
  case body {
    Djot(document) -> djot.render(document, styled_renderer())
    Computed(view) -> view(site)
  }
}

fn render_minimal(body: Body, site: Site) -> List(element.Element(Nil)) {
  case body {
    Djot(document) -> djot.render(document, djot.default_renderer())
    Computed(view) -> view(site)
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
