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
import post

pub fn title() {
  "kevinschweikert.de"
}

pub fn elements(posts: List(post.Post)) -> List(element.Element(a)) {
  let posts_by_year =
    posts
    |> list.group(fn(post) { post.published.year })
    |> dict.to_list()
    |> list.sort(fn(a, b) { int.compare(b.0, a.0) })
  [
    html.h1([], [html.text("kevinschweikert.de")]),
    html.p([], [
      html.text(
        "Hi! I'm Kevin Schweikert, a software engineer with a media technology background and a passion for neapolitan pizza 🍕",
      ),
    ]),
    html.h2([], [html.text("Articles")]),
    html.div([], [
      {
        use <- bool.guard(
          posts == [],
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

fn post_list(posts: List(post.Post)) -> element.Element(a) {
  let posts = posts |> list.sort(posts_by_date)
  html.ol([attribute.class("list-none ps-0")], list.map(posts, post_item))
}

fn posts_by_date(post_a: post.Post, post_b: post.Post) -> order.Order {
  calendar.naive_date_compare(post_b.published, post_a.published)
}

fn post_item(post: post.Post) -> element.Element(a) {
  html.li([], [
    html.a(
      [
        attribute.class("font-bold text-lg"),
        attribute.href("/posts/" <> post.slug <> ".html"),
      ],
      [
        html.text(post.title),
      ],
    ),
    html.p([attribute.class("text-sm mt-0")], [
      html.time(
        [
          attribute.attribute("datetime", helper.date_to_string(post.published)),
        ],
        [
          html.text(abbr_post_date(post)),
        ],
      ),
      html.text(" · "),
      html.text(post.summary),
    ]),
  ])
}

fn abbr_post_date(post: post.Post) -> String {
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
