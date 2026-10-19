import djot/document as doc
import djot/extract
import gleam/dict
import gleam/int
import gleam/list
import lustre/attribute.{attribute}
import lustre/element.{type Element}
import lustre/element/html

pub type Renderer {
  Renderer(
    block: fn(doc.Block, RenderContext) -> Element(Nil),
    inline: fn(doc.Inline, RenderContext) -> Element(Nil),
  )
}

pub opaque type RenderContext {
  RenderContext(renderer: Renderer)
}

pub fn render(doc: doc.Document, renderer: Renderer) -> List(Element(Nil)) {
  let ctx = RenderContext(renderer:)
  blocks(ctx, doc.blocks)
}

pub fn standard() -> Renderer {
  Renderer(block: block, inline:)
}

pub fn blocks(
  ctx: RenderContext,
  nodes: List(doc.Block),
) -> List(Element(Nil)) {
  use node <- list.map(nodes)
  ctx.renderer.block(node, ctx)
}

pub fn inlines(
  ctx: RenderContext,
  nodes: List(doc.Inline),
) -> List(Element(Nil)) {
  use node <- list.map(nodes)
  ctx.renderer.inline(node, ctx)
}

pub fn block(node: doc.Block, ctx: RenderContext) {
  case node {
    doc.ThematicBreak -> html.hr([])
    doc.Paragraph(attributes:, content:) ->
      html.p(to_attributes(attributes), inlines(ctx, content))
    doc.Heading(attributes:, level:, content:) -> {
      let attrs = to_attributes(attributes)
      let elements = inlines(ctx, content)
      case level {
        1 -> html.h1(attrs, elements)
        2 -> html.h2(attrs, elements)
        3 -> html.h3(attrs, elements)
        4 -> html.h4(attrs, elements)
        5 -> html.h5(attrs, elements)
        6 -> html.h6(attrs, elements)
        _ -> html.p(attrs, elements)
      }
    }
    doc.Codeblock(attributes:, language:, code:) -> {
      html.pre(to_attributes(attributes), [
        html.code([attribute("data-lang", language)], [html.text(code)]),
      ])
    }
    doc.RawBlock(content:) -> element.unsafe_raw_html("", "div", [], content)
    doc.BulletList(layout:, style:, items:) -> {
      let list_style_type =
        attribute.style("list-style-type", case style {
          doc.BulletDash -> "''"
          doc.BulletStar -> "disc"
          doc.BulletPlus -> "circle"
        })

      html.ul([list_style_type], list.map(items, list_item(ctx, layout, _)))
    }
    doc.OrderedList(layout:, punctuation:, style:, start:, items:) -> {
      let list_style_type =
        attribute.style("list-style-type", case style {
          doc.NumericOrdinal -> "decimal"
          doc.LowerAlphaOrdinal -> "lower-alpha"
          doc.UpperAlphaOrdinal -> "upper-alpha"
        })

      let punctuation_type = case punctuation {
        doc.FullStop -> "full-stop"
        doc.SingleParen -> "single-paren"
        doc.DoubleParen -> "double-paren"
      }

      html.ol(
        [
          attribute.attribute("start", int.to_string(start)),
          attribute.data("punctuation", punctuation_type),
          list_style_type,
        ],
        list.map(items, list_item(ctx, layout, _)),
      )
    }
    doc.BlockQuote(attributes:, items:) ->
      html.blockquote(to_attributes(attributes), blocks(ctx, items))

    doc.Div(attributes:, items:) ->
      html.div(to_attributes(attributes), blocks(ctx, items))
    doc.Endnotes(footnotes:) -> {
      html.section([attribute.role("doc-endnotes")], [
        html.ol([], list.map(footnotes, endnote(ctx, _))),
      ])
    }
  }
}

fn endnote(
  ctx: RenderContext,
  note: doc.FootnoteEntry,
) -> element.Element(Nil) {
  let back =
    html.a(
      [attribute.href("#" <> note.ref_id), attribute.role("doc-backlink")],
      [html.text("↩")],
    )
  let content = case list.reverse(note.content) {
    [doc.Paragraph(attributes:, content:), ..rest] ->
      list.append(blocks(ctx, list.reverse(rest)), [
        html.p(
          to_attributes(attributes),
          list.append(inlines(ctx, content), [html.text(" "), back]),
        ),
      ])
    _ -> list.append(blocks(ctx, note.content), [back])
  }
  html.li([attribute.id(note.note_id)], content)
}

fn list_item(
  ctx: RenderContext,
  layout: doc.ListLayout,
  item: List(doc.Block),
) -> element.Element(Nil) {
  html.li([], case layout {
    doc.Loose -> blocks(ctx, item)
    doc.Tight ->
      list.flat_map(item, fn(block) {
        case block {
          doc.Paragraph(content:, ..) -> inlines(ctx, content)
          _ -> blocks(ctx, [block])
        }
      })
  })
}

pub fn inline(node: doc.Inline, ctx: RenderContext) {
  case node {
    doc.Linebreak -> html.br([])
    doc.NonBreakingSpace -> html.text(" ")
    doc.Text(text) -> html.text(text)
    doc.Link(attributes:, content:, url:) -> {
      let attributes = to_attributes(attributes)
      html.a([attribute.href(url), ..attributes], inlines(ctx, content))
    }
    doc.Image(attributes:, content:, url:) -> {
      let alt = extract.text(content)
      let attributes = to_attributes(attributes)
      html.img([attribute.src(url), attribute.alt(alt), ..attributes])
    }
    doc.Span(attributes:, content:) ->
      html.span(to_attributes(attributes), inlines(ctx, content))
    doc.Emphasis(content:) -> html.em([], inlines(ctx, content))
    doc.Strong(content:) -> html.strong([], inlines(ctx, content))
    doc.Delete(content:) -> html.del([], inlines(ctx, content))
    doc.Insert(content:) -> html.ins([], inlines(ctx, content))
    doc.Mark(content:) -> html.mark([], inlines(ctx, content))
    doc.Footnote(label:, ref_id:, note_id:) ->
      html.sup([], [
        html.a([attribute.id(ref_id), attribute.href("#" <> note_id)], [
          html.text(label),
        ]),
      ])
    doc.Code(content:) -> html.code([], [html.text(content)])
    doc.MathInline(content:) -> {
      html.span([attribute.class("math inline")], [
        html.text("\\(" <> content <> "\\)"),
      ])
    }
    doc.MathDisplay(content:) -> {
      html.span([attribute.class("math display")], [
        html.text("\\[" <> content <> "\\]"),
      ])
    }
    doc.Symbol(content:) -> html.text(":" <> content <> ":")
    doc.Superscript(content:) -> html.sup([], inlines(ctx, content))
    doc.Subscript(content:) -> html.sub([], inlines(ctx, content))
  }
}

pub fn to_attributes(attrs) {
  use attrs, key, val <- dict.fold(attrs, [])
  [attribute(key, val), ..attrs]
}
