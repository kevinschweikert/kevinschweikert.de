import gleam/int
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp

pub fn date_to_string(date: calendar.Date) -> String {
  let calendar.Date(year:, month:, day:) = date
  let year = year |> int.to_string() |> string.pad_start(4, "0")
  let month =
    month
    |> calendar.month_to_int()
    |> int.to_string()
    |> string.pad_start(2, "0")
  let day = day |> int.to_string() |> string.pad_start(2, "0")

  year <> "-" <> month <> "-" <> day
}

pub fn date_to_humanized_string(date: calendar.Date) -> String {
  let day = date.day |> int.to_string() |> string.pad_start(2, "0")
  let month = date.month |> calendar.month_to_string()
  let year = date.year |> int.to_string()

  month <> " " <> day <> ", " <> year
}

pub fn date_to_datetime(date: calendar.Date) -> String {
  timestamp.from_calendar(
    date,
    calendar.TimeOfDay(0, 0, 0, 0),
    calendar.utc_offset,
  )
  |> timestamp.to_rfc3339(calendar.utc_offset)
}
