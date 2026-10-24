import djot/document as doc
import gleam/dict
import gleam/list
import gleam/result
import gleam/set

pub type Heading {
  Heading(id: String, level: Int, text: String)
}

pub fn headings(doc: doc.Document) -> List(Heading) {
  {
    use acc, node <- doc.fold_blocks(doc, [])
    case node {
      doc.Heading(attributes:, level:, content:) -> [
        Heading(
          id: dict.get(attributes, "id") |> result.unwrap(""),
          text: text(content),
          level:,
        ),
        ..acc
      ]
      _ -> acc
    }
  }
  |> list.reverse()
}

pub fn links(doc: doc.Document) -> List(String) {
  {
    use acc, node <- doc.fold_inlines(doc, [])
    case node {
      doc.Link(url:, ..) -> [url, ..acc]
      doc.Image(url:, ..) -> [url, ..acc]
      _ -> acc
    }
  }
  |> list.reverse()
}

pub fn code_languages(doc: doc.Document) -> set.Set(String) {
  use acc, node <- doc.fold_blocks(doc, set.new())
  case node {
    doc.Codeblock(language:, ..) -> set.insert(acc, language)
    _ -> acc
  }
}

pub fn text(inlines: List(doc.Inline)) -> String {
  use acc, node <- list.fold(inlines, "")

  case node {
    doc.Text(content) -> acc <> content
    doc.NonBreakingSpace -> acc <> " "
    doc.Link(content: content, attributes: _, url: _) -> acc <> text(content)
    doc.Emphasis(content) -> acc <> text(content)
    doc.Strong(content) -> acc <> text(content)
    doc.Code(content) -> acc <> content
    doc.Image(_, _, _) -> acc
    doc.Linebreak -> acc
    doc.MathDisplay(_) -> acc
    doc.MathInline(_) -> acc
    doc.Span(attributes: _, content:) -> acc <> text(content)
    doc.Delete(content:) -> acc <> text(content)
    doc.Insert(content:) -> acc <> text(content)
    doc.Mark(content:) -> acc <> text(content)
    doc.Symbol(content:) -> acc <> content
    doc.Superscript(content:) -> acc <> text(content)
    doc.Subscript(content:) -> acc <> text(content)
    doc.Footnote(label:, ..) -> acc <> label
  }
}
