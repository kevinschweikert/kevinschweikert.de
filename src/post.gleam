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
    date: calendar.Date,
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

  let post = Post(slug:, title:, summary:, date:, elements:) |> layout()
  Ok(post)
}

fn layout(post: Post) -> Post {
  let heading = html.h1([], [html.text(post.title)])
  let datetime =
    attribute.attribute(
      "datetime",
      post.date
        |> date_to_string,
    )
  let date =
    html.time([datetime], [
      html.text(
        post.date
        |> date_to_string,
      ),
    ])

  Post(..post, elements: [heading, date, ..post.elements])
}

pub fn date_to_string(date: calendar.Date) -> String {
  let day = date.day |> int.to_string() |> string.pad_start(2, "0")

  let month =
    date.month
    |> calendar.month_to_int()
    |> int.to_string()
    |> string.pad_start(2, "0")

  let year = date.year |> int.to_string() |> string.pad_start(2, "0")

  [year, month, day]
  |> string.join("-")
}
