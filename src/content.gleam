import gleam/option
import gleam/time/calendar

pub type Revision {
  Revision(hash: String, changed_at: calendar.Date)
}

pub type Source {
  Source(path: String, revision: option.Option(Revision))
}
