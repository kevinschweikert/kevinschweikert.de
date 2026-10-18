import output
import route
import site

pub type Generator =
  fn(site.Site, List(route.Rel)) -> List(output.Output)
