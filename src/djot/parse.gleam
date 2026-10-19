import djot/document as doc
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import jot

type Anchor {
  Anchor(label: String, ref_id: String, note_id: String)
}

type ParseContext {
  ParseContext(doc: jot.Document, anchors: dict.Dict(String, Anchor))
}

pub fn parse(content: String) -> doc.Document {
  content
  |> jot.parse()
  |> document()
}

fn document(doc: jot.Document) -> doc.Document {
  let keys = doc.footnotes |> dict.keys |> list.sort(string.compare)
  let ctx = ParseContext(doc:, anchors: anchors(keys))
  let blocks = map_containers(doc.content, ctx)
  case keys {
    [] -> doc.Document(blocks)
    _ -> doc.Document(list.append(blocks, [doc.Endnotes(endnotes(keys, ctx))]))
  }
}

fn map_containers(
  nodes: List(jot.Container),
  ctx: ParseContext,
) -> List(doc.Block) {
  use node <- list.map(nodes)
  case node {
    jot.ThematicBreak -> doc.ThematicBreak
    jot.Paragraph(attributes:, content:) ->
      doc.Paragraph(attributes:, content: map_inlines(content, ctx))
    jot.Heading(attributes:, level:, content:) ->
      doc.Heading(attributes:, level:, content: map_inlines(content, ctx))
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
        items: list.map(items, map_containers(_, ctx)),
      )
    jot.OrderedList(layout:, punctuation:, ordinal:, start:, items:) ->
      doc.OrderedList(
        layout: map_layout(layout),
        punctuation: map_punctuation(punctuation),
        style: map_ordinal_style(ordinal),
        start:,
        items: list.map(items, map_containers(_, ctx)),
      )
    jot.BlockQuote(attributes:, items:) ->
      doc.BlockQuote(attributes:, items: map_containers(items, ctx))
    jot.Div(class: _, attributes:, items:) ->
      doc.Div(attributes:, items: map_containers(items, ctx))
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

// jot seeds every footnote key with a leading "^"
fn anchors(keys: List(String)) -> dict.Dict(String, Anchor) {
  keys
  |> list.index_map(fn(key, index) {
    let assert "^" <> name = key
    let anchor =
      Anchor(
        label: int.to_string(index + 1),
        ref_id: "fnref-" <> name,
        note_id: "fn-" <> name,
      )
    #(key, anchor)
  })
  |> dict.from_list
}

fn endnotes(keys: List(String), ctx: ParseContext) -> List(doc.FootnoteEntry) {
  use key <- list.map(keys)
  let assert Ok(Anchor(label:, ref_id:, note_id:)) = dict.get(ctx.anchors, key)
  let assert Ok(content) = dict.get(ctx.doc.footnotes, key)
  doc.FootnoteEntry(
    label:,
    ref_id:,
    note_id:,
    content: map_containers(content, ctx),
  )
}

fn map_inlines(nodes: List(jot.Inline), ctx: ParseContext) -> List(doc.Inline) {
  use node <- list.map(nodes)
  case node {
    jot.Link(attributes:, content:, destination:) -> {
      let #(url, resolved_attributes) = resolve_url(ctx, destination)
      let attributes = dict.merge(attributes, resolved_attributes)
      doc.Link(attributes:, content: map_inlines(content, ctx), url:)
    }
    jot.Image(attributes:, content:, destination:) -> {
      let #(url, resolved_attributes) = resolve_url(ctx, destination)
      let attributes = dict.merge(attributes, resolved_attributes)
      doc.Image(attributes:, content: map_inlines(content, ctx), url:)
    }
    jot.Linebreak -> doc.Linebreak
    jot.NonBreakingSpace -> doc.NonBreakingSpace
    jot.Text(text) -> doc.Text(text)
    jot.Span(attributes:, content:) ->
      doc.Span(attributes:, content: map_inlines(content, ctx))
    jot.Emphasis(content:) -> doc.Emphasis(content: map_inlines(content, ctx))
    jot.Strong(content:) -> doc.Strong(content: map_inlines(content, ctx))
    jot.Delete(content:) -> doc.Delete(content: map_inlines(content, ctx))
    jot.Insert(content:) -> doc.Insert(content: map_inlines(content, ctx))
    jot.Mark(content:) -> doc.Mark(content: map_inlines(content, ctx))
    jot.Superscript(content:) ->
      doc.Superscript(content: map_inlines(content, ctx))
    jot.Subscript(content:) -> doc.Subscript(content: map_inlines(content, ctx))
    jot.Footnote(reference:) -> {
      let assert Ok(Anchor(label:, ref_id:, note_id:)) =
        dict.get(ctx.anchors, reference)
      doc.Footnote(label:, ref_id:, note_id:)
    }
    jot.Code(content:) -> doc.Code(content:)
    jot.MathInline(content:) -> doc.MathInline(content:)
    jot.MathDisplay(content:) -> doc.MathDisplay(content:)
    jot.Symbol(content:) -> doc.Symbol(content:)
  }
}

fn resolve_url(
  ctx: ParseContext,
  destination: jot.Destination,
) -> #(String, doc.Attributes) {
  case destination {
    jot.Reference(ref) -> {
      let attributes = case dict.get(ctx.doc.reference_attributes, ref) {
        Ok(attrs) -> attrs
        Error(_) -> dict.new()
      }

      let url = case dict.get(ctx.doc.references, ref) {
        Ok(url) -> url
        Error(_) -> ref
      }

      #(url, attributes)
    }
    jot.Url(url) -> #(url, dict.new())
  }
}
