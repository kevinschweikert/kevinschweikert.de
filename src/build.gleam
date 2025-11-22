import gleam/dict
import gleam/io
import gleam/list

// Some functions for rendering pages
import pages/blog/post1
import pages/index

// Import the static site generator
import lustre/attribute
import lustre/element
import lustre/element/html.{body, head, html, link}
import lustre/ssg
import lustre/ssg/djot

const catppuccin_styles_url = "https://cdn.jsdelivr.net/npm/@catppuccin/palette/css/catppuccin.css"

const catppuccin_styles_checksum = "sha512-rostBe3y8SV6rNeApitsio4hw7OxN4yIdzrVdtbad5zUkoYk3+EicAFjt2zHsHC0LvxTuTFdRFWTbwokYPbDMg=="

pub fn main() {
  let posts = [
    #("post-1", djot.render(post1.render(), djot.default_renderer())),
  ]

  let post_links =
    posts |> list.map(fn(post: #(String, List(element.Element(a)))) { post.0 })

  let index =
    root(djot.render(index.render(post_links), djot.default_renderer()))

  let build =
    ssg.new("./priv")
    |> ssg.add_static_route("/", index)
    |> ssg.add_dynamic_route("/posts", posts |> dict.from_list(), root)
    |> ssg.add_static_dir("./assets")
    |> ssg.build

  case build {
    Ok(_) -> io.println("Build succeeded!")
    Error(e) -> {
      echo e
      io.println("Build failed!")
    }
  }
}

fn root(elements) {
  let head_content = [
    link([
      attribute.rel("stylesheet"),
      attribute.href(catppuccin_styles_url),
      attribute.attribute("integrity", catppuccin_styles_checksum),
      attribute.crossorigin("anonymous"),
    ]),
    link([
      attribute.rel("stylesheet"),
      attribute.href("/app.css"),
    ]),
  ]
  html([], [head([], head_content), body([attribute.class("page")], elements)])
}
