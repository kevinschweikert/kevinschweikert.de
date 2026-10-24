import gleam/list
import output
import route
import site

pub fn generate(
  site: site.Site,
  _paths: List(route.Rel),
) -> List(output.Output) {
  use asset <- list.map(site.assets)
  output.Output(
    path: site.asset_rel(asset),
    contents: output.Copy(from: asset.source),
  )
}
