import glimra
import lustre/ssg/djot

pub fn custom_renderer(_metadata, highlighter) {
  let base = djot.default_renderer()
  djot.Renderer(..base, codeblock: glimra.codeblock_renderer(highlighter))
}
