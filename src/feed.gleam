import gleam/list
import layout
import lustre/attribute
import lustre/element
import lustre/ssg/atom
import post

pub fn build(title: String, posts: List(post.Post)) {
  let root = [
    atom.title([], title),
    atom.id([], "kevinschweikert.de"),
    atom.updated([], "2023-11-23T18:00:00Z"),
    atom.link([attribute.rel("self"), attribute.href("/feed")]),
    atom.author([], [atom.name([], "Kevin Schweikert")]),
  ]
  let entries =
    list.map(posts, fn(post: post.Post) {
      atom.entry([], [
        atom.title([], post.title),
        atom.link([
          attribute.rel("alternate"),
          attribute.href("/posts/" <> post.slug),
        ]),
        atom.id([], "some id"),
        atom.updated([], post.date),
        atom.summary([], post.summary),
        atom.content(
          [],
          post.elements |> layout.layout() |> element.to_string(),
        ),
      ])
    })
  atom.feed([], root |> list.append(entries))
}
