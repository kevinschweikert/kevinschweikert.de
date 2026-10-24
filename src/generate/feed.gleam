import atom
import component
import gleam/list
import gleam/option
import gleam/time/calendar
import gleam/time/timestamp
import gleam/uri
import helper
import lustre/attribute
import lustre/element
import output
import route
import site

pub fn generate(
  site: site.Site,
  _paths: List(route.Rel),
) -> List(output.Output) {
  let site.Site(config:, pages:, ..) = site
  let feed =
    atom.feed([], [
      atom.title([], config.title),
      atom.id([], uri.to_string(config.base)),
      atom.updated([], now()),
      atom.link([
        attribute.rel("self"),
        route.Feed
          |> route.target
          |> route.abs(on: config.base)
          |> component.absolute_href(),
      ]),
      atom.author([], [atom.name([], config.author)]),
      ..{
        let pages =
          list.sort(pages, fn(a, b) {
            calendar.naive_date_compare(b.published, a.published)
          })
        use page <- list.filter_map(pages)
        case page.route {
          route.Article(slug:) -> {
            let id = slug
            let title = page.meta.title
            let description = page.meta.description
            let url = site.abs_path(page, site.config.base)
            let published = page.published
            let updated =
              site.updated_date(page) |> option.unwrap(page.published)
            let html =
              page
              |> site.to_minimal_elements(site)
              |> element.fragment()
              |> element.to_string()
            Ok(
              atom.entry([], [
                atom.title([], title),
                atom.link([
                  attribute.rel("alternate"),
                  component.absolute_href(url),
                ]),
                atom.id([], id),
                atom.published([], published |> helper.date_to_datetime()),
                atom.updated([], updated |> helper.date_to_datetime()),
                atom.summary([], description),
                atom.content([], html),
              ]),
            )
          }
          _ -> Error(Nil)
        }
      }
    ])
  [
    output.Output(
      path: route.Feed |> route.target,
      contents: component.to_xml_docstring(feed) |> output.Text(),
    ),
  ]
}

fn now() -> String {
  timestamp.system_time() |> timestamp.to_rfc3339(calendar.utc_offset)
}
