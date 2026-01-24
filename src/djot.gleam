// From https://github.com/lustre-labs/ssg
// IMPORTS ---------------------------------------------------------------------

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import jot.{Document}
import lustre/attribute.{attribute}
import lustre/element.{type Element}
import lustre/element/html

// TYPES -----------------------------------------------------------------------

/// A renderer for a djot document knows how to turn each block or inline element
/// into some custom view. That view could be anything, but it's typically a
/// Lustre element.
///
/// Some ideas for other renderers include:
///
/// - A renderer that turns a djot document into a JSON object
/// - A renderer that generates a table of contents
/// - A renderer that generates Nakai elements instead of Lustre ones
///
pub type Renderer(view) {
  Renderer(
    codeblock: fn(Dict(String, String), Option(String), String) -> view,
    emphasis: fn(List(view)) -> view,
    heading: fn(Dict(String, String), Int, List(view)) -> view,
    link: fn(Option(String), Dict(String, String), List(view)) -> view,
    paragraph: fn(Dict(String, String), List(view)) -> view,
    bullet_list: fn(jot.ListLayout, jot.BulletStyle, List(List(view))) -> view,
    ordered_list: fn(
      jot.ListLayout,
      jot.OrdinalPunctuation,
      jot.OrdinalStyle,
      Int,
      List(List(view)),
    ) ->
      view,
    raw_html: fn(String) -> view,
    strong: fn(List(view)) -> view,
    text: fn(String) -> view,
    code: fn(String) -> view,
    image: fn(Option(String), Dict(String, String), String) -> view,
    linebreak: view,
    thematicbreak: view,
    inline_math: fn(String) -> view,
    display_math: fn(String) -> view,
    blockquote: fn(Dict(String, String), List(view)) -> view,
    span: fn(Dict(String, String), String) -> view,
    div: fn(Dict(String, String), List(view)) -> view,
    insert: fn(String) -> view,
    delete: fn(String) -> view,
    mark: fn(String) -> view,
    symbol: fn(String) -> view,
  )
}

// CONSTRUCTORS ----------------------------------------------------------------

/// The default renderer generates some sensible Lustre elements from a djot
/// document. You can use this if you need a quick drop-in renderer for some
/// markup in a Lustre project.
///
/// > **Note**: this does not implement a rich renderer for maths expressions.
/// > Instead, this takes the same approach as djot's own syntax reference and
/// > renders a `<span>` that can be understood by external libraries like
/// > MathJax or KaTeX.
///
pub fn default_renderer() -> Renderer(Element(msg)) {
  let to_attributes = fn(attrs) {
    use attrs, key, val <- dict.fold(attrs, [])
    [attribute(key, val), ..attrs]
  }

  Renderer(
    codeblock: fn(attrs, lang, code) {
      let lang = option.unwrap(lang, "text")
      html.pre(to_attributes(attrs), [
        html.code([attribute("data-lang", lang)], [html.text(code)]),
      ])
    },
    emphasis: fn(content) { html.em([], content) },
    heading: fn(attrs, level, content) {
      case level {
        1 -> html.h1(to_attributes(attrs), content)
        2 -> html.h2(to_attributes(attrs), content)
        3 -> html.h3(to_attributes(attrs), content)
        4 -> html.h4(to_attributes(attrs), content)
        5 -> html.h5(to_attributes(attrs), content)
        6 -> html.h6(to_attributes(attrs), content)
        _ -> html.p(to_attributes(attrs), content)
      }
    },
    link: fn(destination, attributes, content) {
      let attributes = to_attributes(attributes)

      case destination {
        option.None -> html.span(attributes, content)
        option.Some(url) -> html.a([attribute.href(url), ..attributes], content)
      }
    },
    paragraph: fn(attrs, content) { html.p(to_attributes(attrs), content) },
    bullet_list: fn(layout, style, items) {
      let list_style_type =
        attribute.style("list-style-type", case style {
          jot.BulletDash -> "''"
          jot.BulletStar -> "disc"
          jot.BulletPlus -> "circle"
        })

      html.ul([list_style_type], {
        list.map(items, fn(item) {
          case layout {
            jot.Tight -> html.li([], item)
            jot.Loose -> html.li([], [html.p([], item)])
          }
        })
      })
    },
    ordered_list: fn(layout, punctuation, ordinal, start, items) {
      let list_style_type =
        attribute.style("list-style-type", case ordinal {
          jot.NumericOrdinal -> "decimal"
          jot.LowerAlphaOrdinal -> "lower-alpha"
          jot.UpperAlphaOrdinal -> "upper-alpha"
        })

      let punctuation_type = case punctuation {
        jot.FullStop -> "full-stop"
        jot.SingleParen -> "single-paren"
        jot.DoubleParen -> "double-paren"
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
              jot.Tight -> html.li([], item)
              jot.Loose -> html.li([], [html.p([], item)])
            }
          })
        },
      )
    },
    raw_html: fn(content) { element.unsafe_raw_html("", "div", [], content) },
    strong: fn(content) { html.strong([], content) },
    text: fn(text) { html.text(text) },
    code: fn(content) { html.code([], [html.text(content)]) },
    image: fn(destination, attributes, alt) {
      let attributes = to_attributes(attributes)
      case destination {
        option.None -> html.span(attributes, [html.text(alt)])
        option.Some(url) ->
          html.img([attribute.src(url), attribute.alt(alt), ..attributes])
      }
    },
    linebreak: html.br([]),
    thematicbreak: html.hr([]),
    inline_math: fn(math) {
      html.span([attribute.class("math inline")], [
        html.text("\\(" <> math <> "\\)"),
      ])
    },
    display_math: fn(math) {
      html.span([attribute.class("math display")], [
        html.text("\\[" <> math <> "\\]"),
      ])
    },
    blockquote: fn(attrs, content) {
      html.blockquote(to_attributes(attrs), content)
    },
    span: fn(attrs, content) {
      html.span(to_attributes(attrs), [html.text(content)])
    },
    div: fn(attrs, content) { html.div(to_attributes(attrs), content) },
    insert: fn(content) { html.ins([], [html.text(content)]) },
    delete: fn(content) { html.del([], [html.text(content)]) },
    mark: fn(content) { html.mark([], [html.text(content)]) },
    symbol: fn(content) {
      html.span([attribute.class("symbol")], [html.text(content)])
    },
  )
}

// CONVERSIONS -----------------------------------------------------------------

/// Render a djot document using the given renderer.
///
pub fn render(content: String, renderer: Renderer(view)) -> List(view) {
  let Document(content:, references:, reference_attributes:, footnotes: _) =
    jot.parse(content)

  content
  |> list.map(render_block(_, references, reference_attributes, renderer))
}

fn render_block(
  block: jot.Container,
  references: Dict(String, String),
  reference_attributes: Dict(String, Dict(String, String)),
  renderer: Renderer(view),
) -> view {
  case block {
    jot.Paragraph(attrs, inline) -> {
      renderer.paragraph(
        attrs,
        list.map(inline, render_inline(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }

    jot.Heading(attrs, level, inline) -> {
      renderer.heading(
        attrs,
        level,
        list.map(inline, render_inline(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }

    jot.Codeblock(attrs, language, code) -> {
      renderer.codeblock(attrs, language, code)
    }

    jot.ThematicBreak -> {
      renderer.thematicbreak
    }

    jot.RawBlock(content) -> {
      renderer.raw_html(content)
    }

    jot.BulletList(layout, style, items) -> {
      renderer.bullet_list(
        layout,
        style,
        list.map(
          items,
          list.map(_, render_block(
            _,
            references,
            reference_attributes,
            renderer,
          )),
        ),
      )
    }

    jot.OrderedList(layout:, punctuation:, ordinal:, start:, items:) -> {
      renderer.ordered_list(
        layout,
        punctuation,
        ordinal,
        start,
        list.map(
          items,
          list.map(_, render_block(
            _,
            references,
            reference_attributes,
            renderer,
          )),
        ),
      )
    }
    jot.BlockQuote(attributes:, items:) -> {
      renderer.blockquote(
        attributes,
        list.map(items, render_block(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }
    jot.Div(attributes:, items:) -> {
      renderer.div(
        attributes,
        list.map(items, render_block(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }
  }
}

fn render_inline(
  inline: jot.Inline,
  references: Dict(String, String),
  reference_attributes: Dict(String, Dict(String, String)),
  renderer: Renderer(view),
) -> view {
  case inline {
    jot.Text(text) -> {
      renderer.text(text)
    }

    jot.NonBreakingSpace -> {
      renderer.text(" ")
    }

    jot.Link(content:, destination:, attributes:) -> {
      let #(url, additional_attributes) =
        resolve_references(destination, references, reference_attributes)
      let attributes = dict.merge(attributes, additional_attributes)

      renderer.link(
        url,
        attributes,
        list.map(content, render_inline(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }

    jot.Emphasis(content:) -> {
      renderer.emphasis(
        list.map(content, render_inline(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }

    jot.Strong(content:) -> {
      renderer.strong(
        list.map(content, render_inline(
          _,
          references,
          reference_attributes,
          renderer,
        )),
      )
    }

    jot.Code(content:) -> {
      renderer.code(content)
    }

    jot.Image(content:, destination:, attributes:) -> {
      let #(url, additional_attributes) =
        resolve_references(destination, references, reference_attributes)
      let attributes = dict.merge(attributes, additional_attributes)

      renderer.image(url, attributes, text_content(content))
    }
    jot.Linebreak -> {
      renderer.linebreak
    }

    jot.Footnote(_) -> renderer.text("")

    jot.MathDisplay(content:) -> {
      renderer.display_math(content)
    }

    jot.MathInline(content:) -> {
      renderer.inline_math(content)
    }
    jot.Span(attributes:, content:) -> {
      renderer.span(attributes, text_content(content))
    }

    jot.Insert(content:) -> {
      renderer.insert(text_content(content))
    }
    jot.Delete(content:) -> {
      renderer.delete(text_content(content))
    }
    jot.Mark(content:) -> {
      renderer.mark(text_content(content))
    }
    jot.Symbol(content:) -> {
      renderer.symbol(content)
    }
  }
}

// UTILS -----------------------------------------------------------------------

fn resolve_references(
  destination: jot.Destination,
  references: Dict(String, String),
  reference_attributes: Dict(String, Dict(String, String)),
) -> #(Option(String), Dict(String, String)) {
  case destination {
    jot.Reference(ref) -> {
      let attributes = case dict.get(reference_attributes, ref) {
        Ok(attrs) -> attrs
        Error(_) -> dict.new()
      }

      case dict.get(references, ref) {
        Ok(url) -> #(option.Some(url), attributes)
        Error(_) -> #(option.None, attributes)
      }
    }
    jot.Url(url) -> #(option.Some(url), dict.new())
  }
}

fn text_content(segments: List(jot.Inline)) -> String {
  use text, inline <- list.fold(segments, "")

  case inline {
    jot.Text(content) -> text <> content
    jot.NonBreakingSpace -> text <> " "
    jot.Link(content: content, attributes: _, destination: _) ->
      text <> text_content(content)
    jot.Emphasis(content) -> text <> text_content(content)
    jot.Strong(content) -> text <> text_content(content)
    jot.Code(content) -> text <> content
    jot.Image(_, _, _) -> text
    jot.Linebreak -> text
    jot.Footnote(_) -> text
    jot.MathDisplay(_) -> text
    jot.MathInline(_) -> text
    jot.Span(attributes: _, content:) -> text <> text_content(content)
    jot.Delete(content:) -> text <> text_content(content)
    jot.Insert(content:) -> text <> text_content(content)
    jot.Mark(content:) -> text <> text_content(content)
    jot.Symbol(content:) -> text <> content
  }
}
