import envoy
import gleam/dict
import gleam/io
import gleam/list
import gleam/result

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

  let index = layout.layout(index.render(posts))
  let feed = feed.build(index.title(), posts)

  let build =
    ssg.new("./priv")
    |> ssg.add_static_route("/", index)
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
