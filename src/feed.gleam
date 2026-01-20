import config
import gleam/list
import gleam/option
import gleam/time/calendar
import gleam/time/timestamp
import helper
import lustre/attribute
import lustre/element
import lustre/element/html
import lustre/ssg/atom
import post

pub fn build(title: String, posts: List(post.Post)) {
  atom.feed([], [
    atom.title([], title),
    atom.id([], config.domain()),
    // [TODO]: don't update on each build
    atom.updated([], now()),
    atom.link([
      attribute.rel("self"),
      attribute.href(config.root_url() <> "/feed.xml"),
    ]),
    atom.author([], [atom.name([], config.author())]),
    ..{
      use post <- list.map(posts)
      atom.entry([], [
        atom.title([], post.title),
        atom.link([
          attribute.rel("alternate"),
          attribute.href(config.root_url() <> "/posts/" <> post.slug),
        ]),
        atom.id([], post.slug),
        atom.published([], post.published |> helper.date_to_datetime()),
        atom.updated(
          [],
          post.updated
            |> option.unwrap(post.published)
            |> helper.date_to_datetime(),
        ),
        atom.summary([], post.summary),
        atom.content(
          [],
          // [TODO]: don't add server rendered highlighting
          post.elements |> html.article([], _) |> element.to_string(),
        ),
      ])
    }
  ])
}

fn now() {
  timestamp.system_time() |> timestamp.to_rfc3339(calendar.utc_offset)
}
