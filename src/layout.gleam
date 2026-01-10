import gleam/list
import gleam/option
import gleam/uri
import glimra
import lustre/attribute
import lustre/element
import lustre/element/html
import lustre/ssg/opengraph
import post

pub fn layout(elements) {
  let assert Ok(uri) = uri.parse("https://kevinschweikert.de")
  let og = [
    // TODO: centralize description info
    opengraph.description(
      "Hi! I'm Kevin Schweikert, a software engineer with a media technology background and a passion for neapolitan pizza 🍕",
    ),
    // TODO: centralize title info
    opengraph.title("Kevin Schweikert"),
    opengraph.url(uri),
    opengraph.website(),
  ]
  html(elements, option.Some(og))
}

pub fn post_layout(post: post.Post) {
  let assert Ok(uri) = uri.parse("/posts/" <> post.slug)
  let og = [
    opengraph.description(post.summary),
    opengraph.title(post.title),
    opengraph.url(uri),
    opengraph.website(),
  ]
  html(post.elements, option.Some(og))
}

fn html(elements, additional_headers: option.Option(List(element.Element(Nil)))) {
  html.html([], [
    // TODO: centralize title info
    head("Kevin Schweikert", option.None, additional_headers),
    html.body([], [
      html.header([], [
        html.nav([], [
          html.a([attribute.href("/index.html")], [html.text("Home")]),
          html.a([attribute.href("/about.html")], [html.text("About")]),
          html.a([attribute.href("/contact.html")], [html.text("Contact")]),
          html.a([attribute.href("/now.html")], [html.text("Now")]),
          html.a([attribute.href("/uses.html")], [html.text("Uses")]),
        ]),
      ]),
      html.main([attribute.class("page")], elements),
      html.footer([], []),
    ]),
  ])
}

fn head(title: String, _description: option.Option(String), additional_headers) {
  let add_headers = case additional_headers {
    option.Some(headers) -> headers
    _ -> []
  }

  html.head(
    [],
    [
      html.title([], title),
      html.meta([attribute.attribute("charset", "utf-8")]),
      html.script(
        [
          attribute.attribute("async", "true"),
          attribute.src(
            "https://plausible.kevinschweikert.de/js/pa-Xjy2lqLyTD7zfUCRDjM3k.js",
          ),
        ],
        "",
      ),
      html.script(
        [],
        "window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};
  plausible.init()",
      ),
      // TODO: centralize author info
      html.meta([
        attribute.attribute("name", "author"),
        attribute.attribute("content", "Kevin Schweikert"),
      ]),
      html.meta([
        attribute.attribute("name", "viewport"),
        attribute.attribute("content", "width=device-width, initial-scale=1"),
      ]),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/app.css"),
      ]),
      glimra.link_static_stylesheet(),
    ]
      |> list.append(add_headers),
  )
}
