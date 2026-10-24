import component
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import gleam/order
import gleam/string
import gleam/time/calendar
import helper
import lustre/attribute
import lustre/element
import lustre/element/html
import route
import site

pub fn view(site: site.Site) -> List(element.Element(Nil)) {
  let posts_by_year =
    site.pages
    |> list.filter(fn(page) {
      case page.route {
        route.Article(_) -> True
        _ -> False
      }
    })
    |> list.group(fn(post) { post.published.year })
    |> dict.to_list()
    |> list.sort(fn(a, b) { int.compare(b.0, a.0) })
  [
    html.h2([], [html.text("Articles")]),
    html.div([], [
      {
        use <- bool.guard(
          posts_by_year == [],
          html.p([], [
            html.text("Sorry, no Articles yet. Check in again soon!"),
          ]),
        )
        html.ol([attribute.class("list-none ps-0")], {
          use #(year, posts) <- list.map(posts_by_year)
          html.li([], [
            html.h3([], [html.text(int.to_string(year))]),
            post_list(posts),
          ])
        })
      },
    ]),
  ]
}

fn post_list(posts: List(site.Page)) -> element.Element(a) {
  let posts = posts |> list.sort(posts_by_date)
  html.ol([attribute.class("list-none ps-0")], list.map(posts, post_item))
}

fn posts_by_date(post_a: site.Page, post_b: site.Page) -> order.Order {
  calendar.naive_date_compare(post_b.published, post_a.published)
}

fn post_item(post: site.Page) -> element.Element(a) {
  html.li([], [
    html.a(
      [
        attribute.class("font-bold text-lg"),
        post |> site.rel_path() |> component.relative_href(),
      ],
      [
        html.text(post.meta.title),
      ],
    ),
    html.p([attribute.class("text-sm mt-0")], [
      html.time(
        [
          attribute.attribute(
            "datetime",
            post.published |> helper.date_to_string(),
          ),
        ],
        [
          html.text(abbr_post_date(post)),
        ],
      ),
      html.text(" · "),
      html.text(post.meta.description),
    ]),
  ])
}

fn abbr_post_date(post: site.Page) -> String {
  let calendar.Date(year: _, month:, day:) = post.published
  let month_abbr = case month {
    calendar.January -> "JAN"
    calendar.February -> "FEB"
    calendar.March -> "MAR"
    calendar.April -> "APR"
    calendar.May -> "MAY"
    calendar.June -> "JUN"
    calendar.July -> "JUL"
    calendar.August -> "AUG"
    calendar.September -> "SEP"
    calendar.October -> "OCT"
    calendar.November -> "NOV"
    calendar.December -> "DEC"
  }

  month_abbr <> " " <> int.to_string(day) |> string.pad_start(2, "0")
}
