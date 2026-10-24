import djot/document as doc
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import jot

pub fn parse(content: String) -> doc.Document {
  content
  |> jot.parse()
  |> document()
}

fn document(input: jot.Document) -> doc.Document {
  let body = doc.Document(map_containers(input.content, input))

  case referenced(body) {
    [] -> body
    names -> {
      let doc.Document(blocks:) = body
      doc.Document(list.append(blocks, [doc.Endnotes(endnotes(names, input))]))
      |> renumber(names)
    }
  }
}

// jot seeds every footnote key and reference with a leading "^"
fn name(key: String) -> String {
  let assert "^" <> name = key
  name
}

fn ref_id(key: String) -> String {
  "fnref-" <> name(key)
}

fn note_id(key: String) -> String {
  "fn-" <> name(key)
}

fn map_containers(
  nodes: List(jot.Container),
  input: jot.Document,
) -> List(doc.Block) {
  use node <- list.map(nodes)
  case node {
    jot.ThematicBreak -> doc.ThematicBreak
    jot.Paragraph(attributes:, content:) ->
      doc.Paragraph(attributes:, content: map_inlines(content, input))
    jot.Heading(attributes:, level:, content:) ->
      doc.Heading(attributes:, level:, content: map_inlines(content, input))
    jot.Codeblock(attributes:, language:, content:) ->
      doc.Codeblock(
        attributes:,
        language: option.unwrap(language, "text"),
        code: content,
      )
    jot.RawBlock(content:) -> doc.RawBlock(content:)
    jot.BulletList(layout:, style:, items:) ->
      doc.BulletList(
        layout: map_layout(layout),
        style: map_bullet_style(style),
        items: list.map(items, map_containers(_, input)),
      )
    jot.OrderedList(layout:, punctuation:, ordinal:, start:, items:) ->
      doc.OrderedList(
        layout: map_layout(layout),
        punctuation: map_punctuation(punctuation),
        style: map_ordinal_style(ordinal),
        start:,
        items: list.map(items, map_containers(_, input)),
      )
    jot.BlockQuote(attributes:, items:) ->
      doc.BlockQuote(attributes:, items: map_containers(items, input))
    jot.Div(class: _, attributes:, items:) ->
      doc.Div(attributes:, items: map_containers(items, input))
  }
}

fn map_ordinal_style(value: jot.OrdinalStyle) -> doc.OrdinalStyle {
  case value {
    jot.NumericOrdinal -> doc.NumericOrdinal
    jot.LowerAlphaOrdinal -> doc.LowerAlphaOrdinal
    jot.UpperAlphaOrdinal -> doc.UpperAlphaOrdinal
  }
}

fn map_punctuation(
  punctuation: jot.OrdinalPunctuation,
) -> doc.OrdinalPunctuation {
  case punctuation {
    jot.FullStop -> doc.FullStop
    jot.SingleParen -> doc.SingleParen
    jot.DoubleParen -> doc.DoubleParen
  }
}

fn map_bullet_style(style: jot.BulletStyle) -> doc.BulletStyle {
  case style {
    jot.BulletDash -> doc.BulletDash
    jot.BulletStar -> doc.BulletStar
    jot.BulletPlus -> doc.BulletPlus
  }
}

fn map_layout(layout: jot.ListLayout) -> doc.ListLayout {
  case layout {
    jot.Tight -> doc.Tight
    jot.Loose -> doc.Loose
  }
}

fn referenced(body: doc.Document) -> List(String) {
  {
    use acc, node <- doc.fold_inlines(body, [])
    case node {
      doc.Footnote(label:, ..) -> [label, ..acc]
      _ -> acc
    }
  }
  |> list.reverse
  |> list.unique
}

fn renumber(document: doc.Document, names: List(String)) -> doc.Document {
  let numbers =
    names
    |> list.index_map(fn(name, index) { #(name, int.to_string(index + 1)) })
    |> dict.from_list

  use node <- doc.map_inlines(document)
  case node {
    doc.Footnote(label:, ..) as note -> {
      let label = result.unwrap(dict.get(numbers, label), label)
      doc.Footnote(..note, label:)
    }
    _ -> node
  }
}

fn endnotes(
  names: List(String),
  input: jot.Document,
) -> List(doc.FootnoteEntry) {
  use name <- list.map(names)
  let key = "^" <> name
  let assert Ok(content) = dict.get(input.footnotes, key)
  doc.FootnoteEntry(
    ref_id: ref_id(key),
    note_id: note_id(key),
    content: map_containers(content, input),
  )
}

fn map_inlines(
  nodes: List(jot.Inline),
  input: jot.Document,
) -> List(doc.Inline) {
  use node <- list.map(nodes)
  case node {
    jot.Link(attributes:, content:, destination:) -> {
      let #(url, resolved_attributes) = resolve_url(input, destination)
      let attributes = dict.merge(attributes, resolved_attributes)
      doc.Link(attributes:, content: map_inlines(content, input), url:)
    }
    jot.Image(attributes:, content:, destination:) -> {
      let #(url, resolved_attributes) = resolve_url(input, destination)
      let attributes = dict.merge(attributes, resolved_attributes)
      doc.Image(attributes:, content: map_inlines(content, input), url:)
    }
    jot.Linebreak -> doc.Linebreak
    jot.NonBreakingSpace -> doc.NonBreakingSpace
    jot.Text(text) -> doc.Text(text)
    jot.Span(attributes:, content:) ->
      doc.Span(attributes:, content: map_inlines(content, input))
    jot.Emphasis(content:) -> doc.Emphasis(content: map_inlines(content, input))
    jot.Strong(content:) -> doc.Strong(content: map_inlines(content, input))
    jot.Delete(content:) -> doc.Delete(content: map_inlines(content, input))
    jot.Insert(content:) -> doc.Insert(content: map_inlines(content, input))
    jot.Mark(content:) -> doc.Mark(content: map_inlines(content, input))
    jot.Superscript(content:) ->
      doc.Superscript(content: map_inlines(content, input))
    jot.Subscript(content:) ->
      doc.Subscript(content: map_inlines(content, input))
    jot.Footnote(reference:) ->
      doc.Footnote(
        label: name(reference),
        ref_id: ref_id(reference),
        note_id: note_id(reference),
      )
    jot.Code(content:) -> doc.Code(content:)
    jot.MathInline(content:) -> doc.MathInline(content:)
    jot.MathDisplay(content:) -> doc.MathDisplay(content:)
    jot.Symbol(content:) -> doc.Symbol(content:)
  }
}

fn resolve_url(
  input: jot.Document,
  destination: jot.Destination,
) -> #(String, doc.Attributes) {
  case destination {
    jot.Reference(ref) -> {
      let attributes = case dict.get(input.reference_attributes, ref) {
        Ok(attrs) -> attrs
        Error(_) -> dict.new()
      }

      let url = case dict.get(input.references, ref) {
        Ok(url) -> url
        Error(_) -> ref
      }

      #(url, attributes)
    }
    jot.Url(url) -> #(url, dict.new())
  }
}
