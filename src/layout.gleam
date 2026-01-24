import config
import gleam/option
import lustre/attribute
import lustre/element
import lustre/element/html
import opengraph
import page
import route

const plausible_source = "https://plausible.kevinschweikert.de/js/pa-Xjy2lqLyTD7zfUCRDjM3k.js"

const plausible_script = "window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(i){plausible.o=i||{}};
  plausible.init()"

pub fn root(page: page.Page) {
  html.html([attribute.lang("en")], [
    html.head([], [
      html.title([], page.meta.title),
      html.meta([attribute.attribute("charset", "utf-8")]),
      html.meta([
        attribute.name("description"),
        attribute.content(page.meta.description),
      ]),
      html.link([
        attribute.rel("preconnect"),
        attribute.href("https://plausible.kevinschweikert.de"),
      ]),
      html.script(
        [
          attribute.attribute("async", "true"),
          attribute.src(plausible_source),
        ],
        "",
      ),
      html.script([], plausible_script),
      html.meta([
        attribute.attribute("name", "author"),
        attribute.attribute("content", config.author()),
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
      opengraph.description(page.meta.description),
      opengraph.title(page.meta.title),
      opengraph.url(page.abs_path(page)),

      {
        case page.route {
          page.Article(_) ->
            html.meta([
              attribute.attribute("property", "og:type"),
              attribute.content("article"),
            ])
          _ -> opengraph.website()
        }
      },
      {
        case page.og_image_url(page) {
          option.Some(rel) ->
            opengraph.image(rel |> route.abs() |> route.abs_uri())
          option.None -> element.fragment([])
        }
      },
    ]),
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
          page.to_elements(page),
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
              html.a([attribute.href("https://github.com/lustre-labs/lustre")], [
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
