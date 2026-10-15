import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import jot
import lustre/element.{type Element}

pub type Attributes =
  dict.Dict(String, String)

pub type ListLayout {
  Tight
  Loose
}

pub type BulletStyle {
  BulletDash
  BulletStar
  BulletPlus
}

pub type OrdinalPunctuation {
  FullStop
  SingleParen
  DoubleParen
}

pub type OrdinalStyle {
  NumericOrdinal
  LowerAlphaOrdinal
  UpperAlphaOrdinal
}

pub type FootnoteEntry {
  FootnoteEntry(
    label: String,
    content: List(Container),
    ref_id: String,
    note_id: String,
  )
}

pub type Container {
  ThematicBreak
  Paragraph(attributes: Attributes, content: List(Inline))
  Heading(attributes: Attributes, level: Int, content: List(Inline))
  Codeblock(attributes: Attributes, language: String, content: String)
  RawBlock(content: String)
  BulletList(
    layout: ListLayout,
    style: BulletStyle,
    items: List(List(Container)),
  )
  OrderedList(
    layout: ListLayout,
    punctuation: OrdinalPunctuation,
    style: OrdinalStyle,
    start: Int,
    items: List(List(Container)),
  )
  BlockQuote(attributes: Attributes, items: List(Container))
  Div(attributes: Attributes, items: List(Container))
  Endnotes(footnotes: List(FootnoteEntry))
}

pub type Inline {
  Linebreak
  NonBreakingSpace
  Text(String)
  Link(attributes: Attributes, content: List(Inline), url: String)
  Image(attributes: Attributes, content: List(Inline), url: String)
  Span(attributes: Attributes, content: List(Inline))
  Emphasis(content: List(Inline))
  Strong(content: List(Inline))
  Delete(content: List(Inline))
  Insert(content: List(Inline))
  Mark(content: List(Inline))
  Superscript(content: List(Inline))
  Subscript(content: List(Inline))
  Footnote(ref_id: String, note_id: String, label: String)
  Code(content: String)
  MathInline(content: String)
  MathDisplay(content: String)
  Symbol(content: String)
}

pub type Renderer {
  Renderer(
    container: fn(Container, Context) -> Element(Nil),
    inline: fn(Inline, Context) -> Element(Nil),
  )
}

pub opaque type Context {
  Context(renderer: Renderer)
}

type ResolveContext {
  ResolveContext(doc: jot.Document, anchors: dict.Dict(String, Inline))
}

pub fn render(doc: jot.Document, renderer: Renderer) -> List(Element(Nil)) {
  let containers = document(doc)
  let ctx = Context(renderer:)
  blocks(ctx, containers)
}

pub fn document(doc: jot.Document) -> List(Container) {
  let anchors = anchors(doc.footnotes)
  let resolve_ctx = ResolveContext(doc:, anchors:)
  let containers = map_containers(doc.content, resolve_ctx)
  case dict.to_list(doc.footnotes) {
    [] -> containers
    _ -> list.append(containers, [Endnotes(extract_footnotes(resolve_ctx))])
  }
}

fn map_containers(
  nodes: List(jot.Container),
  ctx: ResolveContext,
) -> List(Container) {
  use node <- list.map(nodes)
  case node {
    jot.ThematicBreak -> ThematicBreak
    jot.Paragraph(attributes:, content:) ->
      Paragraph(attributes:, content: map_inlines(content, ctx))
    jot.Heading(attributes:, level:, content:) ->
      Heading(attributes:, level:, content: map_inlines(content, ctx))
    jot.Codeblock(attributes:, language:, content:) ->
      Codeblock(
        attributes:,
        language: option.unwrap(language, "text"),
        content:,
      )
    jot.RawBlock(content:) -> RawBlock(content:)
    jot.BulletList(layout:, style:, items:) ->
      BulletList(
        layout: map_layout(layout),
        style: map_bullet_style(style),
        items: list.map(items, map_containers(_, ctx)),
      )
    jot.OrderedList(layout:, punctuation:, ordinal:, start:, items:) ->
      OrderedList(
        layout: map_layout(layout),
        punctuation: map_punctuation(punctuation),
        style: map_ordinal_style(ordinal),
        start:,
        items: list.map(items, map_containers(_, ctx)),
      )
    jot.BlockQuote(attributes:, items:) ->
      BlockQuote(attributes:, items: map_containers(items, ctx))
    jot.Div(class: _, attributes:, items:) ->
      Div(attributes:, items: map_containers(items, ctx))
  }
}

fn map_ordinal_style(value: jot.OrdinalStyle) -> OrdinalStyle {
  case value {
    jot.NumericOrdinal -> NumericOrdinal
    jot.LowerAlphaOrdinal -> LowerAlphaOrdinal
    jot.UpperAlphaOrdinal -> UpperAlphaOrdinal
  }
}

fn map_punctuation(punctuation: jot.OrdinalPunctuation) -> OrdinalPunctuation {
  case punctuation {
    jot.FullStop -> FullStop
    jot.SingleParen -> SingleParen
    jot.DoubleParen -> DoubleParen
  }
}

fn map_bullet_style(style: jot.BulletStyle) -> BulletStyle {
  case style {
    jot.BulletDash -> BulletDash
    jot.BulletStar -> BulletStar
    jot.BulletPlus -> BulletPlus
  }
}

fn map_layout(layout: jot.ListLayout) -> ListLayout {
  case layout {
    jot.Tight -> Tight
    jot.Loose -> Loose
  }
}

fn anchors(
  footnotes: dict.Dict(String, List(jot.Container)),
) -> dict.Dict(String, Inline) {
  let footnotes = dict.to_list(footnotes)
  let #(_, entries) =
    list.map_fold(footnotes, 1, fn(index, footnote) {
      let #(key, _content) = footnote
      let assert "^" <> ref = key
      #(
        index + 1,
        #(
          key,
          Footnote(
            ref_id: "fnref-" <> ref,
            note_id: "fn-" <> ref,
            label: int.to_string(index),
          ),
        ),
      )
    })
  dict.from_list(entries)
}

fn extract_footnotes(ctx: ResolveContext) -> List(FootnoteEntry) {
  use #(key, content) <- list.map(dict.to_list(ctx.doc.footnotes))
  let assert Ok(Footnote(label:, ref_id:, note_id:)) =
    dict.get(ctx.anchors, key)
  FootnoteEntry(label:, ref_id:, note_id:, content: map_containers(content, ctx))
}

fn map_inlines(nodes: List(jot.Inline), ctx: ResolveContext) -> List(Inline) {
  use node <- list.map(nodes)
  case node {
    jot.Link(attributes:, content:, destination:) -> {
      let #(url, resolved_attributes) = resolve_url(ctx, destination)
      let attributes = dict.merge(attributes, resolved_attributes)
      Link(attributes:, content: map_inlines(content, ctx), url:)
    }
    jot.Image(attributes:, content:, destination:) -> {
      let #(url, resolved_attributes) = resolve_url(ctx, destination)
      let attributes = dict.merge(attributes, resolved_attributes)
      Image(attributes:, content: map_inlines(content, ctx), url:)
    }
    jot.Linebreak -> Linebreak
    jot.NonBreakingSpace -> NonBreakingSpace
    jot.Text(text) -> Text(text)
    jot.Span(attributes:, content:) ->
      Span(attributes:, content: map_inlines(content, ctx))
    jot.Emphasis(content:) -> Emphasis(content: map_inlines(content, ctx))
    jot.Strong(content:) -> Strong(content: map_inlines(content, ctx))
    jot.Delete(content:) -> Delete(content: map_inlines(content, ctx))
    jot.Insert(content:) -> Insert(content: map_inlines(content, ctx))
    jot.Mark(content:) -> Mark(content: map_inlines(content, ctx))
    jot.Superscript(content:) -> Superscript(content: map_inlines(content, ctx))
    jot.Subscript(content:) -> Subscript(content: map_inlines(content, ctx))
    jot.Footnote(reference:) -> {
      let assert Ok(footnote) = dict.get(ctx.anchors, reference)
      footnote
    }
    jot.Code(content:) -> Code(content:)
    jot.MathInline(content:) -> MathInline(content:)
    jot.MathDisplay(content:) -> MathDisplay(content:)
    jot.Symbol(content:) -> Symbol(content:)
  }
}

pub fn blocks(ctx: Context, nodes: List(Container)) -> List(Element(Nil)) {
  use node <- list.map(nodes)
  ctx.renderer.container(node, ctx)
}

pub fn inlines(ctx: Context, nodes: List(Inline)) -> List(Element(Nil)) {
  use node <- list.map(nodes)
  ctx.renderer.inline(node, ctx)
}

fn resolve_url(
  ctx: ResolveContext,
  destination: jot.Destination,
) -> #(String, Attributes) {
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
