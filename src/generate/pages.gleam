import gleam/list
import layout
import lustre/element
import output
import route
import site

pub fn generate(
  site: site.Site,
  _paths: List(route.Rel),
) -> List(output.Output) {
  use page <- list.map(site.pages)
  output.Output(
    path: site.rel_path(page),
    contents: page
      |> layout.root(site)
      |> element.to_document_string()
      |> output.Text,
  )
}
