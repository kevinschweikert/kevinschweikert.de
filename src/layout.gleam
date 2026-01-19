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
  html.html([attribute.lang("en")], [
    // TODO: centralize title info
    head("Kevin Schweikert", option.None, additional_headers),
    html.body(
      [
        attribute.class(
          "flex flex-col items-center bg-ctp-base text-ctp-text p-4 h-screen",
        ),
      ],
      [
        html.header([], [
          html.nav(
            [
              attribute.class(
                "flex flex-row gap-4 wrap mb-4 font-bold text-ctp-blue-900 dark:text-ctp-blue-200",
              ),
            ],
            [
              html.a([attribute.href("/index.html")], [html.text("Home")]),
              html.a([attribute.href("/about.html")], [html.text("About")]),
              html.a([attribute.href("/contact.html")], [html.text("Contact")]),
              html.a([attribute.href("/now.html")], [html.text("Now")]),
              html.a([attribute.href("/uses.html")], [html.text("Uses")]),
            ],
          ),
        ]),
        html.main(
          [
            attribute.class(
              "flex-1 min-w-0 w-full max-w-prose mx-auto prose dark:prose-invert prose-catppuccin prose-img:rounded-lg  prose-a:no-underline prose-a:hover:underline prose-pre:text-ctp-base dark:prose-pre:text-ctp-text",
            ),
          ],
          elements,
        ),
        html.footer(
          [
            attribute.class(
              "text-sm mt-4 p-1 flex flex-col items-center gap-2 ",
            ),
          ],
          [
            html.p([], [
              html.text("Built with "),
              html.a(
                [
                  attribute.href(
                    "https://github.com/kevinschweikert/kevinschweikert.de",
                  ),
                ],
                [html.text("♥︎")],
              ),
              html.text(", "),
              html.a([attribute.href("https://gleam.run/")], [
                html.text("Gleam"),
              ]),
              html.text(" and "),
              html.a([attribute.href("https://github.com/lustre-labs/ssg")], [
                html.text("Lustre"),
              ]),
            ]),
            html.p([attribute.class("text-xs")], [
              html.text("Found an error? Have suggestions? "),
              html.a(
                [
                  attribute.class(
                    "hover:underline text-ctp-blue-900 dark:text-ctp-blue-100",
                  ),
                  attribute.href(
                    "https://github.com/kevinschweikert/kevinschweikert.de/issues",
                  ),
                ],
                [html.text("Open an issue")],
              ),
            ]),
            html.p([], [
              html.a([attribute.href("/impress.html")], [
                html.text("Impress / Impressum"),
              ]),
            ]),
          ],
        ),
      ],
    ),
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
        attribute.name("description"),
        attribute.content(
          "Hi! I'm Kevin Schweikert, a software engineer with a media technology background and a passion for neapolitan pizza 🍕",
        ),
      ]),
      html.link([
        attribute.rel("preconnect"),
        attribute.href("https://plausible.kevinschweikert.de"),
      ]),
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
        attribute.rel("icon"),
        attribute.attribute("type", "image/svg+xml"),
        attribute.href("/favicon.svg"),
      ]),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/style.css"),
      ]),
      glimra.link_static_stylesheet(),
    ]
      |> list.append(add_headers),
  )
}
