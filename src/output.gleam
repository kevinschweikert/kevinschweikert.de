import filepath
import route
import simplifile

pub type Contents {
  Text(String)
  Bytes(BitArray)
}

pub type Output {
  Output(path: route.Rel, contents: Contents)
}

pub fn write(to out_dir: String, output output: Output) -> Nil {
  let path = route.fs_rel_path(output.path) |> filepath.join(out_dir, _)

  let assert Ok(Nil) =
    path |> filepath.directory_name |> simplifile.create_directory_all

  let assert Ok(Nil) = case output.contents {
    Text(contents) -> simplifile.write(contents:, to: path)
    Bytes(bits) -> simplifile.write_bits(bits:, to: path)
  }

  Nil
}
