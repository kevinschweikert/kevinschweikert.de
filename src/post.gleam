import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/time/calendar
import lustre/attribute
import lustre/element/html
import render
import tom

// Import the static site generator
import lustre/element
import lustre/ssg/djot
import simplifile

pub type Post {
  Post(
    slug: String,
    title: String,
    date: String,
    summary: String,
    elements: List(element.Element(Nil)),
  )
}

pub type PostError {
  FileError(simplifile.FileError)
  ParseError(tom.ParseError)
}

pub fn get_posts(highlighter) {
  use posts <- result.try(
    simplifile.read_directory("./src/pages/posts")
    |> result.map_error(FileError),
  )

  use filename <- list.try_map(posts)
  use content <- result.try(
    simplifile.read("./src/pages/posts/" <> filename)
    |> result.map_error(FileError),
  )

  use metadata <- result.try(
    djot.metadata(content) |> result.map_error(ParseError),
  )

  use elements <- result.try(
    djot.render_with_metadata(content, fn(metadata) {
      render.custom_renderer(metadata, highlighter)
    })
    |> result.map_error(ParseError),
  )

  let assert Ok(title) = tom.get_string(metadata, ["title"])
  let assert Ok(slug) = tom.get_string(metadata, ["slug"])
  let assert Ok(summary) = tom.get_string(metadata, ["summary"])
  let assert Ok(date) = tom.get_date(metadata, ["date"])
  let date =
    date.year
    |> int.to_string()
    |> string.append("-")
    |> string.append(date.month |> calendar.month_to_int() |> int.to_string())
    |> string.append("-")
    |> string.append(date.day |> int.to_string())

  let post = Post(slug:, title:, summary:, date:, elements:) |> layout()
  Ok(post)
}

fn layout(post: Post) -> Post {
  let heading = html.h1([], [html.text(post.title)])
  let datetime = attribute.attribute("datetime", post.date)
  let date = html.time([datetime], [html.text(post.date)])

  Post(..post, elements: [heading, date, ..post.elements])
}
