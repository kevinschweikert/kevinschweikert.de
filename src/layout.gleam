import gleam/list
import gleam/option
import gleam/uri
import glimra
import lustre/attribute
import lustre/element
import lustre/element/html
import lustre/ssg/opengraph
import post

const catppuccin_styles_url = "https://cdn.jsdelivr.net/npm/@catppuccin/palette/css/catppuccin.css"

const catppuccin_styles_checksum = "sha512-rostBe3y8SV6rNeApitsio4hw7OxN4yIdzrVdtbad5zUkoYk3+EicAFjt2zHsHC0LvxTuTFdRFWTbwokYPbDMg=="

pub fn layout(elements) {
  let assert Ok(uri) = uri.parse("https://kevinschweikert.de")
  let og = [
    opengraph.description(
      "Hi! I'm Kevin Schweikert, a software engineer with a media technology background and a passion for neapolitan pizza 🍕",
    ),
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
    head("Kevin Schweikerts Blog", option.None, additional_headers),
    html.body([attribute.class("page")], elements),
    html.footer([], [html.text("hi rom")]),
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
      html.meta([
        attribute.attribute("name", "viewport"),
        attribute.attribute("content", "width=device-width, initial-scale=1"),
      ]),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href(catppuccin_styles_url),
        attribute.attribute("integrity", catppuccin_styles_checksum),
        attribute.crossorigin("anonymous"),
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
