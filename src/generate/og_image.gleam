import config
import generate
import gleam/list
import helper
import output
import route
import site
import typst

pub fn generate(template: String) -> generate.Generator {
  fn(site: site.Site, _paths: List(route.Rel)) -> List(output.Output) {
    use page <- list.map(site.pages)
    let assert Ok(png) =
      typst.new(template)
      |> typst.add_binding("title", page.meta.title)
      |> typst.add_binding("description", page.meta.description)
      |> typst.add_binding(
        "date",
        page.published |> helper.date_to_humanized_string(),
      )
      |> typst.add_binding("domain", config.domain(site.config))
      |> typst.render()

    output.Output(path: route.og_image(page.route), contents: output.Bytes(png))
  }
}
