import config
import git
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/string
import gleam/time/calendar
import helper
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
    published: calendar.Date,
    updated: option.Option(calendar.Date),
    summary: String,
    elements: List(element.Element(Nil)),
    git_short_hash: option.Option(String),
    git_hash: option.Option(String),
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

  // filename.dj -> filename
  let slug = string.drop_end(filename, 3)

  let assert Ok(draft) = tom.get_bool(metadata, ["draft"])
  let assert Ok(title) = tom.get_string(metadata, ["title"])
  let assert Ok(summary) = tom.get_string(metadata, ["summary"])
  let assert Ok(published) = tom.get_date(metadata, ["published"])

  let git_short_hash =
    git.short_hash("src/pages/posts/" <> filename) |> option.from_result()
  let git_hash =
    git.full_hash("src/pages/posts/" <> filename) |> option.from_result()

  let last_changed_at = git.last_changed_at("src/pages/posts/" <> filename)

  let updated = case last_changed_at {
    Ok(up) ->
      case calendar.naive_date_compare(up, published) {
        order.Lt | order.Eq -> option.None
        order.Gt -> option.Some(up)
      }
    Error(_) -> option.None
  }

  let post =
    Post(
      draft:,
      slug:,
      title:,
      summary:,
      published:,
      updated:,
      elements:,
      git_short_hash:,
      git_hash:,
    )
    |> layout()
  Ok(post)
}

fn layout(post: Post) -> Post {
  let title = html.h1([], [html.text(post.title)])
  let datetime = fn(date) {
    attribute.attribute("datetime", helper.date_to_string(date))
  }

  let hash =
    case post.git_short_hash, post.git_hash {
      option.Some(short_hash), option.Some(hash) -> [
        html.text(" · "),
        html.a(
          [
            attribute.class("text-sm"),
            attribute.href(config.repo() <> "/commit/" <> hash),
          ],
          [
            html.text(short_hash),
          ],
        ),
      ]
      _, _ -> []
    }
    |> element.fragment()

  let updated =
    case post.updated {
      option.Some(updated) -> [
        html.text(" · "),
        html.time([attribute.class("text-sm"), datetime(updated)], [
          html.text("updated on "),
          html.text(updated |> helper.date_to_humanized_string),
        ]),
      ]
      option.None -> []
    }
    |> element.fragment()

  let published =
    html.time([attribute.class("text-sm"), datetime(post.published)], [
      html.text("Published on "),
      html.text(
        post.published
        |> helper.date_to_humanized_string,
      ),
    ])

  Post(..post, elements: [
    html.article([], [title, published, updated, hash, ..post.elements]),
  ])
}
