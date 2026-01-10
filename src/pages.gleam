import lustre/ssg/djot
import simplifile

pub fn from_file(filename: String) {
  let assert Ok(djot) = simplifile.read("./src/pages/" <> filename)
  djot.render(djot, djot.default_renderer())
}
