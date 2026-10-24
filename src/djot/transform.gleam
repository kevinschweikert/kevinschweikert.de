import djot/document as doc
import gleam/result
import gleam/string
import gleam/uri

pub fn absolute_urls(doc: doc.Document, against page: uri.Uri) -> doc.Document {
  use node <- doc.map_inlines(doc)
  case node {
    doc.Link(url:, ..) as link -> doc.Link(..link, url: absolute(url, page))
    doc.Image(url:, ..) as image -> doc.Image(..image, url: absolute(url, page))
    _ -> node
  }
}

// uri.merge discards a trailing slash but our canonical representation wants it
fn absolute(url: String, page: uri.Uri) -> String {
  {
    use parsed <- result.try(uri.parse(url))
    use merged <- result.try(uri.merge(page, parsed))
    let path = case
      string.ends_with(parsed.path, "/") && !string.ends_with(merged.path, "/")
    {
      True -> merged.path <> "/"
      _ -> merged.path
    }

    Ok(uri.to_string(uri.Uri(..merged, path:)))
  }
  |> result.unwrap(url)
}
