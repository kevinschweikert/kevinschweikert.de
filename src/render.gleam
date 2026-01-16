import gleam/dict
import gleam/option
import glimra
import lustre/attribute
import lustre/element/html
import lustre/ssg/djot

pub fn custom_renderer(_metadata, highlighter) {
  let to_attributes = fn(attrs) {
    use attrs, key, val <- dict.fold(attrs, [])
    [attribute.attribute(key, val), ..attrs]
  }

  let base = djot.default_renderer()
  djot.Renderer(
    ..base,
    codeblock: glimra.codeblock_renderer(highlighter),
    image: fn(destination, attributes, alt) {
      let attributes = to_attributes(attributes)
      case destination {
        option.None -> html.span(attributes, [html.text(alt)])
        option.Some(url) ->
          html.figure([], [
            html.img([attribute.src(url), attribute.alt(alt), ..attributes]),
            html.figcaption([], [html.text(alt)]),
          ])
      }
    },
  )
}
