import gleam/list
import gleam/time/timestamp
import post
import webls/sitemap

// [TODO]: put in gleam.toml
const domain = "kevinschweikert.de"

pub fn build(posts: List(post.Post)) {
  sitemap.sitemap("https://" <> domain <> "/sitemap.xml")
  |> sitemap.with_sitemap_last_modified(timestamp.system_time())
  |> sitemap.with_sitemap_items([
    sitemap.item("https://" <> domain <> "/about.html"),
    sitemap.item("https://" <> domain <> "/uses.html"),
    sitemap.item("https://" <> domain <> "/contact.html"),
    sitemap.item("https://" <> domain <> "/now.html"),
    ..{
      use post <- list.map(posts)
      sitemap.item("https://" <> domain <> "/posts/" <> post.slug <> ".html")
    }
  ])
  |> sitemap.to_string()
}
