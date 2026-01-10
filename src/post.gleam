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
    draft: Bool,
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

  let assert Ok(draft) = tom.get_bool(metadata, ["draft"])
  let assert Ok(title) = tom.get_string(metadata, ["title"])
  let assert Ok(slug) = tom.get_string(metadata, ["slug"])
  let assert Ok(summary) = tom.get_string(metadata, ["summary"])
  let assert Ok(date) = tom.get_date(metadata, ["date"])

  let post = Post(draft:, slug:, title:, summary:, date:, elements:) |> layout()
  Ok(post)
}

fn layout(post: Post) -> Post {
  let title = html.h1([], [html.text(post.title)])
  let datetime =
    attribute.attribute(
      "datetime",
      post.date
        |> date_to_string,
    )
  let date =
    html.time([datetime], [
      html.text("Published on "),
      html.text(
        post.date
        |> date_to_string,
      ),
    ])

  Post(..post, elements: [title, date, ..post.elements])
}

pub fn date_to_string(date: calendar.Date) -> String {
  let day = date.day |> int.to_string() |> string.pad_start(2, "0")
  let month_abbr = date.month |> to_month_abbr()
  let year = date.year |> int.to_string()

  month_abbr <> " " <> day <> ", " <> year
}

fn to_month_abbr(month: calendar.Month) {
  case month {
    calendar.January -> "Jan"
    calendar.February -> "Feb"
    calendar.March -> "Mar"
    calendar.April -> "Apr"
    calendar.May -> "May"
    calendar.June -> "Jun"
    calendar.July -> "Jul"
    calendar.August -> "Aug"
    calendar.September -> "Sep"
    calendar.October -> "Oct"
    calendar.November -> "Nov"
    calendar.December -> "Dec"
  }
}
