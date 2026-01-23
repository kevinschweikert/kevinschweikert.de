import gleam/dict
import gleam/erlang/atom
import gleam/list

@external(erlang, "Elixir.Typst", "render_to_png")
fn render_to_png(
  markup: String,
  bindings: List(#(atom.Atom, String)),
  opts: List(TypstOption),
) -> Result(List(BitArray), String)

pub type TypstConfig {
  TypstConfig(
    markup: String,
    bindings: dict.Dict(String, String),
    options: List(TypstOption),
  )
}

pub type TypstOption {
  RootDir(String)
  ExtraFonts(List(String))
  PixelsPerPt(Int)
  Assets(List(#(String, BitArray)))
}

pub type TypstError {
  Empty
  Message(String)
  Unknown
}

pub fn new(markup: String) {
  TypstConfig(markup:, bindings: dict.new(), options: [])
}

pub fn add_binding(
  config: TypstConfig,
  key: String,
  value: String,
) -> TypstConfig {
  TypstConfig(..config, bindings: dict.insert(config.bindings, key, value))
}

pub fn set_options(
  config: TypstConfig,
  options: List(TypstOption),
) -> TypstConfig {
  TypstConfig(..config, options: options)
}

pub fn render(config: TypstConfig) -> Result(BitArray, TypstError) {
  let bindings = to_keyword_list(config.bindings)
  case render_to_png(config.markup, bindings, config.options) {
    Ok([]) -> Error(Empty)
    Ok([png, ..]) -> Ok(png)
    Error(message) -> Error(Message(message))
  }
}

fn to_keyword_list(
  pairs: dict.Dict(String, String),
) -> List(#(atom.Atom, String)) {
  pairs
  |> dict.to_list
  |> list.map(fn(pair) {
    let #(key, value) = pair
    #(atom.create(key), value)
  })
}
