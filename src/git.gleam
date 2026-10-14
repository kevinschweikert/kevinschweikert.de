import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import shellout

pub type Error {
  /// git could not run, or this is not a repository.
  Unavailable(status: Int, message: String)
  /// git ran and knows nothing about this path.
  Untracked
  /// git ran and printed something unexpected.
  BadOutput(String)
}

pub fn full_hash(filepath: String) -> Result(String, Error) {
  run(with: ["rev-list", "-1", "HEAD", "--", filepath])
}

pub fn short_hash(filepath: String) -> Result(String, Error) {
  run(with: ["rev-list", "--abbrev-commit", "-1", "HEAD", "--", filepath])
}

fn last_change(filepath: String) -> Result(String, Error) {
  run(with: ["log", "-1", "--format=%cI", "--", filepath])
}

pub fn last_changed_at(filepath: String) -> Result(calendar.Date, Error) {
  use output <- result.try(last_change(filepath))
  use ts <- result.try(
    timestamp.parse_rfc3339(output)
    |> result.replace_error(BadOutput(output)),
  )
  let #(date, _time) = timestamp.to_calendar(ts, calendar.utc_offset)
  Ok(date)
}

fn run(with args: List(String)) -> Result(String, Error) {
  use output <- result.try(
    shellout.command(run: "git", with: args, in: ".", opt: [])
    |> result.map_error(fn(e) { Unavailable(e.0, e.1) }),
  )

  case string.trim(output) {
    "" -> Error(Untracked)
    trimmed -> Ok(trimmed)
  }
}
