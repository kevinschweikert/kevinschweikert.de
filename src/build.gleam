import config
import envoy
import gleam/dict
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import helper
import page.{Page, Website}
import simplifile
import sitemap
import typst

// Some functions for rendering pages
import feed
import index
import layout
import post

import glimra
import glimra/theme

// Import the static site generator
import lustre/ssg

pub fn main() {
  let blog_env = envoy.get("BLOG_ENV") |> result.unwrap("PROD")
  let show_draft = case blog_env {
    "PROD" | "prod" -> False
    _ -> True
  }

  let syntax_highlighter =
    glimra.new_syntax_highlighter()
    |> glimra.set_theme(theme.default_theme())

  // TODO: don't hide error as empty list
  let posts = post.get_posts(syntax_highlighter) |> result.unwrap([])
  let posts =
    posts |> list.filter(fn(post) { post.draft == False || show_draft })

  let route_info =
    posts
    |> list.map(fn(post) {
      #(
        post.slug,
        Page(
          title: post.title,
          description: post.summary,
          url: config.url("/posts/" <> post.slug),
          page_type: page.Article,
          image: option.Some(config.url("/images/" <> post.slug <> ".png")),
          elements: post.elements,
        ),
      )
    })
    |> dict.from_list()

  let index =
    Page(
      title: config.title(),
      description: config.description(),
      url: config.url("/"),
      page_type: Website,
      image: option.None,
      elements: index.elements(posts),
    )

  let about =
    Page(
      title: "About",
      description: "A page about me",
      url: config.url("/about"),
      page_type: Website,
      image: option.None,
      elements: page.elements_from_file("about.dj"),
    )

  let contact =
    Page(
      title: "Contact",
      description: "How you can contact me",
      url: config.url("/contact"),
      page_type: Website,
      image: option.None,
      elements: page.elements_from_file("contact.dj"),
    )

  let uses =
    Page(
      title: "Uses",
      description: "What i am using",
      url: config.url("/uses"),
      page_type: Website,
      image: option.None,
      elements: page.elements_from_file("uses.dj"),
    )

  let now =
    Page(
      title: "Now",
      description: "What's up with me right now",
      url: config.url("/now"),
      page_type: Website,
      image: option.None,
      elements: page.elements_from_file("now.dj"),
    )
  let impress =
    Page(
      title: "Impress",
      description: "Legal stuff",
      url: config.url("/impress"),
      page_type: Website,
      image: option.None,
      elements: page.elements_from_file("impress.dj"),
    )

  let feed = feed.build(config.title(), posts)

  let assert Ok(Nil) =
    sitemap.build(posts) |> simplifile.write("./assets/sitemap.xml", _)

  let assert Ok(markup) = simplifile.read("src/template.typ")
  list.each(posts, fn(post) {
    let assert Ok(png) =
      typst.new(markup)
      |> typst.add_binding("title", post.title)
      |> typst.add_binding("summary", post.summary)
      |> typst.add_binding(
        "date",
        post.published |> helper.date_to_humanized_string(),
      )
      |> typst.add_binding("domain", config.domain())
      |> typst.render()

    simplifile.write_bits("assets/images/" <> post.slug <> ".png", png)
  })

  let build =
    ssg.new("./priv")
    |> ssg.add_static_route(index.url.path, layout.layout(index))
    |> ssg.add_static_route(about.url.path, layout.layout(about))
    |> ssg.add_static_route(contact.url.path, layout.layout(contact))
    |> ssg.add_static_route(uses.url.path, layout.layout(uses))
    |> ssg.add_static_route(now.url.path, layout.layout(now))
    |> ssg.add_static_route(impress.url.path, layout.layout(impress))
    |> ssg.add_dynamic_route("/posts", route_info, layout.layout)
    |> ssg.add_static_dir("./assets")
    |> ssg.add_static_xml("/feed", feed)
    |> ssg.build

  case build {
    Ok(_) -> io.println("Build succeeded!")
    Error(e) -> {
      echo e
      io.println("Build failed!")
    }
  }
}
