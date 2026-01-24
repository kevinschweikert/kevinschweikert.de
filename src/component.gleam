import gleam/string
import gleam/time/calendar
import gleam/uri
import helper
import lustre/attribute
import lustre/element
import lustre/element/html
import route

pub fn to_xml_docstring(element: element.Element(a)) {
  element
  |> element.to_string()
  |> string.append("<?xml version='1.0' encoding='UTF-8'?>", _)
}

pub fn relative_href(rel: route.Rel) -> attribute.Attribute(a) {
  attribute.href(rel |> route.rel_string())
}

pub fn absolute_href(abs: route.Abs) -> attribute.Attribute(a) {
  attribute.href(abs |> route.abs_string())
}

fn date_attr(date: calendar.Date) -> attribute.Attribute(a) {
  attribute.attribute("datetime", helper.date_to_string(date))
}

pub fn time(date: calendar.Date) -> element.Element(a) {
  html.time([date_attr(date)], [
    html.text(date |> helper.date_to_humanized_string),
  ])
}

pub fn link(uri: uri.Uri, text: String) -> element.Element(a) {
  html.a(
    [
      uri |> uri.to_string() |> attribute.href,
    ],
    [
      html.text(text),
    ],
  )
}
