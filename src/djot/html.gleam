import djot/render.{type Container, type Context, type Inline, type Renderer}
import gleam/dict
import gleam/int
import gleam/list
import lustre/attribute.{attribute}
import lustre/element
import lustre/element/html

pub fn renderer() -> Renderer {
  render.Renderer(container: container, inline:)
}

pub fn container(node: Container, ctx: render.Context) {
  case node {
    render.ThematicBreak -> html.hr([])
    render.Paragraph(attributes:, content:) ->
      html.p(to_attributes(attributes), render.inlines(ctx, content))
    render.Heading(attributes:, level:, content:) -> {
      let attrs = to_attributes(attributes)
      let elements = render.inlines(ctx, content)
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
    render.Codeblock(attributes:, language:, content:) -> {
      html.pre(to_attributes(attributes), [
        html.code([attribute("data-lang", language)], [html.text(content)]),
      ])
    }
    render.RawBlock(content:) -> element.unsafe_raw_html("", "div", [], content)
    render.BulletList(layout:, style:, items:) -> {
      let list_style_type =
        attribute.style("list-style-type", case style {
          render.BulletDash -> "''"
          render.BulletStar -> "disc"
          render.BulletPlus -> "circle"
        })

      html.ul([list_style_type], {
        list.map(items, fn(item) {
          case layout {
            render.Tight -> html.li([], render.blocks(ctx, item))
            render.Loose -> html.li([], [html.p([], render.blocks(ctx, item))])
          }
        })
      })
    }
    render.OrderedList(layout:, punctuation:, style:, start:, items:) -> {
      let list_style_type =
        attribute.style("list-style-type", case style {
          render.NumericOrdinal -> "decimal"
          render.LowerAlphaOrdinal -> "lower-alpha"
          render.UpperAlphaOrdinal -> "upper-alpha"
        })

      let punctuation_type = case punctuation {
        render.FullStop -> "full-stop"
        render.SingleParen -> "single-paren"
        render.DoubleParen -> "double-paren"
      }

      html.ol(
        [
          attribute.attribute("start", int.to_string(start)),
          attribute.data("punctuation", punctuation_type),
          list_style_type,
        ],
        {
          list.map(items, fn(item) {
            case layout {
              render.Tight -> html.li([], render.blocks(ctx, item))
              render.Loose ->
                html.li([], [html.p([], render.blocks(ctx, item))])
            }
          })
        },
      )
    }
    render.BlockQuote(attributes:, items:) ->
      html.blockquote(to_attributes(attributes), render.blocks(ctx, items))

    render.Div(attributes:, items:) ->
      html.div(to_attributes(attributes), render.blocks(ctx, items))
    render.Endnotes(footnotes:) -> {
      html.ol(
        [],
        list.map(footnotes, fn(footnote) {
          html.li(
            [attribute.id(footnote.note_id)],
            render.blocks(ctx, footnote.content),
          )
        }),
      )
    }
  }
}

pub fn inline(node: Inline, ctx: Context) {
  case node {
    render.Linebreak -> html.br([])
    render.NonBreakingSpace -> html.text(" ")
    render.Text(text) -> html.text(text)
    render.Link(attributes:, content:, url:) -> {
      let attributes = to_attributes(attributes)
      html.a([attribute.href(url), ..attributes], render.inlines(ctx, content))
    }
    render.Image(attributes:, content:, url:) -> {
      let alt = text_content(content)
      let attributes = to_attributes(attributes)
      html.img([attribute.src(url), attribute.alt(alt), ..attributes])
    }
    render.Span(attributes:, content:) ->
      html.span(to_attributes(attributes), render.inlines(ctx, content))
    render.Emphasis(content:) -> html.em([], render.inlines(ctx, content))
    render.Strong(content:) -> html.strong([], render.inlines(ctx, content))
    render.Delete(content:) -> html.del([], render.inlines(ctx, content))
    render.Insert(content:) -> html.ins([], render.inlines(ctx, content))
    render.Mark(content:) -> html.mark([], render.inlines(ctx, content))
    render.Footnote(ref_id:, note_id:, label:) -> {
      html.sup([], [
        html.a(
          [attribute.id(ref_id), attribute.href("#" <> note_id)],
          [html.text(label)],
        ),
      ])
    }
    render.Code(content:) -> html.code([], [html.text(content)])
    render.MathInline(content:) -> {
      html.span([attribute.class("math inline")], [
        html.text("\\(" <> content <> "\\)"),
      ])
    }
    render.MathDisplay(content:) -> {
      html.span([attribute.class("math inline")], [
        html.text("\\[" <> content <> "\\]"),
      ])
    }
    render.Symbol(content:) -> html.text(":" <> content <> ":")
    render.Superscript(content:) -> html.sup([], render.inlines(ctx, content))
    render.Subscript(content:) -> html.sub([], render.inlines(ctx, content))
  }
}

pub fn to_attributes(attrs) {
  use attrs, key, val <- dict.fold(attrs, [])
  [attribute(key, val), ..attrs]
}

pub fn text_content(segments: List(render.Inline)) -> String {
  use text, inline <- list.fold(segments, "")

  case inline {
    render.Text(content) -> text <> content
    render.NonBreakingSpace -> text <> " "
    render.Link(content: content, attributes: _, url: _) ->
      text <> text_content(content)
    render.Emphasis(content) -> text <> text_content(content)
    render.Strong(content) -> text <> text_content(content)
    render.Code(content) -> text <> content
    render.Image(_, _, _) -> text
    render.Linebreak -> text
    render.MathDisplay(_) -> text
    render.MathInline(_) -> text
    render.Span(attributes: _, content:) -> text <> text_content(content)
    render.Delete(content:) -> text <> text_content(content)
    render.Insert(content:) -> text <> text_content(content)
    render.Mark(content:) -> text <> text_content(content)
    render.Symbol(content:) -> text <> content
    render.Superscript(content:) -> text <> text_content(content)
    render.Subscript(content:) -> text <> text_content(content)
    render.Footnote(ref_id: _, note_id: _, label:) -> text <> label
  }
}
