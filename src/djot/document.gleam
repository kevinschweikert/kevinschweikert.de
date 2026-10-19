import gleam/dict
import gleam/list

pub type Document {
  Document(blocks: List(Block))
}

pub type Block {
  ThematicBreak
  Paragraph(attributes: Attributes, content: List(Inline))
  Heading(attributes: Attributes, level: Int, content: List(Inline))
  Codeblock(attributes: Attributes, language: String, code: String)
  RawBlock(content: String)
  BulletList(layout: ListLayout, style: BulletStyle, items: List(List(Block)))
  OrderedList(
    layout: ListLayout,
    punctuation: OrdinalPunctuation,
    style: OrdinalStyle,
    start: Int,
    items: List(List(Block)),
  )
  BlockQuote(attributes: Attributes, items: List(Block))
  Div(attributes: Attributes, items: List(Block))
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
  Footnote(label: String, ref_id: String, note_id: String)
  Code(content: String)
  MathInline(content: String)
  MathDisplay(content: String)
  Symbol(content: String)
}

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
  FootnoteEntry(content: List(Block), ref_id: String, note_id: String)
}

pub fn fold_blocks(doc: Document, from acc: a, with f: fn(a, Block) -> a) -> a {
  use acc, block <- list.fold(doc.blocks, acc)
  fold_block(acc, block, f)
}

pub fn fold_inlines(
  doc: Document,
  from acc: a,
  with f: fn(a, Inline) -> a,
) -> a {
  use acc, block <- fold_blocks(doc, acc)
  list.fold(block_inlines(block), acc, fn(acc, inline) {
    fold_inline(acc, inline, f)
  })
}

pub fn map_blocks(doc: Document, with f: fn(Block) -> Block) -> Document {
  Document(blocks: list.map(doc.blocks, map_block(_, f)))
}

pub fn map_inlines(doc: Document, with f: fn(Inline) -> Inline) -> Document {
  use block <- map_blocks(doc)
  map_block_inlines(block, map_inline(_, f))
}

// Walkers

fn fold_block(acc: a, block: Block, f: fn(a, Block) -> a) -> a {
  let acc = f(acc, block)
  list.fold(block_children(block), acc, fn(acc, inner) {
    fold_block(acc, inner, f)
  })
}

fn fold_inline(acc: a, inline: Inline, f: fn(a, Inline) -> a) -> a {
  let acc = f(acc, inline)
  list.fold(inline_children(inline), acc, fn(acc, inner) {
    fold_inline(acc, inner, f)
  })
}

fn map_block(block: Block, f: fn(Block) -> Block) -> Block {
  block
  |> map_block_children(map_block(_, f))
  |> f
}

fn map_inline(inline: Inline, f: fn(Inline) -> Inline) -> Inline {
  inline
  |> map_inline_children(map_inline(_, f))
  |> f
}

// Shape helpers

fn block_children(block: Block) -> List(Block) {
  case block {
    ThematicBreak -> []
    Paragraph(attributes: _, content: _) -> []
    Heading(attributes: _, level: _, content: _) -> []
    Codeblock(attributes: _, language: _, code: _) -> []
    RawBlock(content: _) -> []
    BulletList(items:, ..) -> list.flatten(items)
    OrderedList(items:, ..) -> list.flatten(items)
    BlockQuote(attributes: _, items:) -> items
    Div(attributes: _, items:) -> items
    Endnotes(footnotes:) ->
      list.flat_map(footnotes, fn(footnote) { footnote.content })
  }
}

fn map_block_children(block: Block, f: fn(Block) -> Block) -> Block {
  case block {
    ThematicBreak
    | Paragraph(..)
    | Heading(..)
    | Codeblock(..)
    | RawBlock(..) -> block
    BulletList(items:, ..) ->
      BulletList(..block, items: list.map(items, list.map(_, f)))
    OrderedList(items:, ..) ->
      OrderedList(..block, items: list.map(items, list.map(_, f)))
    BlockQuote(items:, ..) -> BlockQuote(..block, items: list.map(items, f))
    Div(items:, ..) -> Div(..block, items: list.map(items, f))
    Endnotes(footnotes:) ->
      Endnotes(
        footnotes: list.map(footnotes, fn(footnote) {
          FootnoteEntry(..footnote, content: list.map(footnote.content, f))
        }),
      )
  }
}

fn block_inlines(block: Block) -> List(Inline) {
  case block {
    ThematicBreak -> []
    Paragraph(content:, ..) -> content
    Heading(content:, ..) -> content
    Codeblock(..) -> []
    RawBlock(..) -> []
    BulletList(..) -> []
    OrderedList(..) -> []
    BlockQuote(..) -> []
    Div(..) -> []
    Endnotes(..) -> []
  }
}

fn map_block_inlines(block: Block, f: fn(Inline) -> Inline) -> Block {
  case block {
    ThematicBreak
    | Codeblock(..)
    | RawBlock(..)
    | BulletList(..)
    | OrderedList(..)
    | BlockQuote(..)
    | Div(..)
    | Endnotes(..) -> block
    Paragraph(content:, ..) -> Paragraph(..block, content: list.map(content, f))
    Heading(content:, ..) -> Heading(..block, content: list.map(content, f))
  }
}

fn inline_children(inline: Inline) -> List(Inline) {
  case inline {
    Linebreak
    | NonBreakingSpace
    | Text(_)
    | Footnote(..)
    | Code(..)
    | MathInline(..)
    | MathDisplay(..)
    | Symbol(..) -> []
    Link(attributes: _, content:, url: _) -> content
    Image(attributes: _, content:, url: _) -> content
    Span(attributes: _, content:) -> content
    Emphasis(content:) -> content
    Strong(content:) -> content
    Delete(content:) -> content
    Insert(content:) -> content
    Mark(content:) -> content
    Superscript(content:) -> content
    Subscript(content:) -> content
  }
}

fn map_inline_children(inline: Inline, f: fn(Inline) -> Inline) -> Inline {
  case inline {
    Linebreak
    | NonBreakingSpace
    | Text(_)
    | Footnote(..)
    | Code(..)
    | MathInline(..)
    | MathDisplay(..)
    | Symbol(..) -> inline
    Link(content:, ..) -> Link(..inline, content: list.map(content, f))
    Image(content:, ..) -> Image(..inline, content: list.map(content, f))
    Span(content:, ..) -> Span(..inline, content: list.map(content, f))
    Emphasis(content:) -> Emphasis(content: list.map(content, f))
    Strong(content:) -> Strong(content: list.map(content, f))
    Delete(content:) -> Delete(content: list.map(content, f))
    Insert(content:) -> Insert(content: list.map(content, f))
    Mark(content:) -> Mark(content: list.map(content, f))
    Superscript(content:) -> Superscript(content: list.map(content, f))
    Subscript(content:) -> Subscript(content: list.map(content, f))
  }
}
