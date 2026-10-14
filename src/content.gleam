import git
import gleam/option
import gleam/result
import gleam/time/calendar

pub type Revision {
  Revision(hash: String, changed_at: calendar.Date)
}

pub type Source {
  Source(path: String, revision: option.Option(Revision))
}

pub fn source(path: String) -> option.Option(Source) {
  option.Some(Source(path: path, revision: revision(path)))
}

fn revision(path: String) -> option.Option(Revision) {
  {
    use hash <- result.try(git.full_hash(path))
    use changed_at <- result.map(git.last_changed_at(path))
    Revision(hash:, changed_at:)
  }
  |> option.from_result()
}
