import gleam/dict
import gleam/int
import gleam/list
import gleam/order
import gleam/time/calendar
import lustre/attribute
import lustre/element
import lustre/element/html
import post

pub fn title() {
  "kevinschweikert.de"
}

pub fn render(posts: List(post.Post)) -> List(element.Element(a)) {
  let posts_by_year =
    posts
    |> list.group(fn(post) { post.date.year })
    |> dict.to_list()
    |> list.sort(fn(a, b) { int.compare(b.0, a.0) })
  [
    html.h1([], [html.text("Kevin Schweikert")]),
    html.p([], [
      html.text(
        "Hi! I'm Kevin Schweikert, a software engineer with a media technology background and a passion for neapolitan pizza 🍕",
      ),
    ]),
    html.p([], [
      html.text(
        "This site is work in progress and will soon show my first article.",
      ),
    ]),
    html.h2([], [html.text("Articles")]),
    html.ol([], {
      use #(year, posts) <- list.map(posts_by_year)
      html.li([], [
        html.h2([], [html.text(int.to_string(year))]),
        post_list(posts),
      ])
    }),
  ]
}

fn post_list(posts: List(post.Post)) -> element.Element(a) {
  let posts = posts |> list.sort(posts_by_date)
  html.ol([], list.map(posts, post_item))
}

fn posts_by_date(post_a: post.Post, post_b: post.Post) -> order.Order {
  calendar.naive_date_compare(post_b.date, post_a.date)
}

fn post_item(post: post.Post) -> element.Element(a) {
  html.li([], [
    html.time(
      [attribute.attribute("datetime", post.date_to_string(post.date))],
      [html.text(abbr_post_date(post))],
    ),
    html.text(" "),
    html.a([attribute.href("/posts/" <> post.slug <> ".html")], [
      html.text(post.title),
    ]),
  ])
}

fn abbr_post_date(post: post.Post) -> String {
  let month_abbr = case post.date.month {
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

  month_abbr <> " " <> int.to_string(post.date.day)
}
