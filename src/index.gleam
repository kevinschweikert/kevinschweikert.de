import gleam/list
import lustre/attribute
import lustre/element
import lustre/element/html
import post

pub fn title() {
  "kevinschweikert.de"
}

pub fn render(posts: List(post.Post)) -> List(element.Element(a)) {
  let post_items = list.map(posts, post_item)
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
    html.ul([], post_items),
  ]
}

fn post_item(post: post.Post) -> element.Element(a) {
  let content =
    html.a([attribute.href("/posts/" <> post.slug <> ".html")], [
      html.text(post.title),
    ])
  html.li([], [content])
}
