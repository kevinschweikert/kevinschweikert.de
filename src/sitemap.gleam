import gleam/int
import gleam/list
import gleam/time/calendar
import helper
import lustre/attribute
import lustre/element
import page
import route

pub fn build(items: List(page.SitemapItem)) {
  urlset({
    use item <- list.map(items)

    url([
      loc(item.url |> route.abs_string()),
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
