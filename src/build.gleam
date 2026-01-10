import envoy
import gleam/dict
import gleam/io
import gleam/list
import gleam/result
import pages
import simplifile
import sitemap

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
    |> list.map(fn(post) { #(post.slug, post) })
    |> dict.from_list()

  let index = posts |> index.render() |> layout.layout()
  let about = pages.from_file("about.dj") |> layout.layout()
  let contact = pages.from_file("contact.dj") |> layout.layout()
  let uses = pages.from_file("uses.dj") |> layout.layout()
  let now = pages.from_file("now.dj") |> layout.layout()
  let feed = feed.build(index.title(), posts)

  let assert Ok(Nil) =
    sitemap.build(posts) |> simplifile.write("./assets/sitemap.xml", _)

  let build =
    ssg.new("./priv")
    |> ssg.add_static_route("/", index)
    |> ssg.add_static_route("/about", about)
    |> ssg.add_static_route("/contact", contact)
    |> ssg.add_static_route("/uses", uses)
    |> ssg.add_static_route("/now", now)
    |> ssg.add_dynamic_route("/posts", route_info, layout.post_layout)
    |> ssg.add_static_dir("./assets")
    |> ssg.add_static_xml("/feed", feed)
    |> glimra.add_static_stylesheet(syntax_highlighter: syntax_highlighter)
    |> ssg.build

  case build {
    Ok(_) -> io.println("Build succeeded!")
    Error(e) -> {
      echo e
      io.println("Build failed!")
    }
  }
}
