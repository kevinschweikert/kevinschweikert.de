import gleam/result
import gleam/time/calendar
import gleam/time/timestamp

@external(erlang, "git_ffi", "full_hash")
pub fn full_hash(filepath: String) -> Result(String, Nil)

@external(erlang, "git_ffi", "short_hash")
pub fn short_hash(filepath: String) -> Result(String, Nil)

@external(erlang, "git_ffi", "last_change")
fn last_change(filepath: String) -> Result(String, Nil)

pub fn last_changed_at(filepath: String) -> Result(calendar.Date, Nil) {
  use timestamp <- result.try(last_change(filepath))
  use ts <- result.try(timestamp.parse_rfc3339(timestamp))
  let #(date, _time) = timestamp.to_calendar(ts, calendar.utc_offset)
  Ok(date)
}
