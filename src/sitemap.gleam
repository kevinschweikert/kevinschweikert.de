import gleam/list
import gleam/option
import gleam/time/calendar
import helper
import lustre/attribute
import lustre/element
import route
import site

pub fn build(site: site.Site) {
  let site.Site(config:, pages:) = site
  urlset({
    use page <- list.map(pages)

    url([
      loc(site.abs_path(page, config.base) |> route.abs_string()),
      lastmod(site.updated_date(page) |> option.unwrap(page.published)),
    ])
  })
}

fn urlset(children: List(element.Element(a))) -> element.Element(a) {
  element.element(
    "urlset",
    [
      attribute.attribute(
        "xmlns",
        "http://www.sitemaps.org/schemas/sitemap/0.9",
      ),
    ],
    children,
  )
}

fn url(children: List(element.Element(a))) -> element.Element(a) {
  element.element("url", [], children)
}

fn loc(url: String) {
  element.element("loc", [], [element.text(url)])
}

fn lastmod(date: calendar.Date) {
  element.element("lastmod", [], [
    date |> helper.date_to_string() |> element.text(),
  ])
}
// fn changefreq(freq: String) {
//   element.element("changefreq", [], [element.text(freq)])
// }

// fn priority(prio: String) {
//   element.element("priority", [], [element.text(prio)])
// }
