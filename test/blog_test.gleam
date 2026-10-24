import birdie
import djot/html
import djot/parse
import gleeunit
import lustre/element

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn djot_footnotes_test() {
  "
  Second[^zebra] and third[^apple].

  [^zebra]: Referenced first, sorts last.
  [^apple]: Referenced second, sorts first.
  [^orphan]: Never referenced.
  "
  |> parse.parse()
  |> html.render(html.standard())
  |> element.fragment()
  |> element.to_document_string()
  |> birdie.snap(title: "djot footnotes")
}
