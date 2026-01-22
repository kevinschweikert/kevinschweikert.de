import gleam/option
import gleam/uri
import lustre/element
import lustre/ssg/djot
import simplifile

pub type PageType {
  Website
  Article
}

pub type Page(a) {
  Page(
    title: String,
    description: String,
    url: uri.Uri,
    page_type: PageType,
    image: option.Option(uri.Uri),
    elements: List(element.Element(a)),
  )
}

pub fn elements_from_file(filename: String) -> List(element.Element(a)) {
  let assert Ok(djot) = simplifile.read("./src/pages/" <> filename)
  djot.render(djot, djot.default_renderer())
}
