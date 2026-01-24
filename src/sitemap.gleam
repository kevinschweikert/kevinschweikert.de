import gleam/int
import gleam/list
import gleam/time/calendar
import gleam/uri
import lustre/attribute
import lustre/element
import page
import route

pub fn build(items: List(page.SitemapItem)) {
  urlset({
    use item <- list.map(items)

    url([
      loc(item.url |> route.abs_uri()),
      lastmod(item.lastmod),
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

fn loc(url: uri.Uri) {
  element.element("loc", [], [element.text(uri.to_string(url))])
}

fn lastmod(date: calendar.Date) {
  let calendar.Date(year:, month:, day:) = date
  let datestring =
    int.to_string(year)
    <> "-"
    <> month |> calendar.month_to_int() |> int.to_string()
    <> "-"
    <> int.to_string(day)
  element.element("lastmod", [], [element.text(datestring)])
}
// fn changefreq(freq: String) {
//   element.element("changefreq", [], [element.text(freq)])
// }

// fn priority(prio: String) {
//   element.element("priority", [], [element.text(prio)])
// }
