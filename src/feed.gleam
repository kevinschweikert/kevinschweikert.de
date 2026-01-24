import atom
import component
import config
import gleam/list
import gleam/time/calendar
import gleam/time/timestamp
import helper
import lustre/attribute
import lustre/element
import page
import route

pub fn build(items: List(page.FeedItem)) -> element.Element(a) {
  atom.feed([], [
    atom.title([], config.domain()),
    atom.id([], config.domain()),
    atom.updated([], now()),
    atom.link([
      attribute.rel("self"),
      "/feed.xml"
        |> route.rel_from_string()
        |> route.abs()
        |> component.absolute_href(),
    ]),
    atom.author([], [atom.name([], config.author())]),
    ..{
      use item <- list.map(items)
      atom.entry([], [
        atom.title([], item.title),
        atom.link([
          attribute.rel("alternate"),
          component.absolute_href(item.url),
        ]),
        atom.id([], item.id),
        atom.published([], item.published |> helper.date_to_datetime()),
        atom.updated([], item.updated |> helper.date_to_datetime()),
        atom.summary([], item.description),
        atom.content([], item.html),
      ])
    }
  ])
}

fn now() -> String {
  timestamp.system_time() |> timestamp.to_rfc3339(calendar.utc_offset)
}
