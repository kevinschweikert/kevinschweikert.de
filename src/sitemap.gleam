import config
import gleam/list
import gleam/time/timestamp
import post
import webls/sitemap

pub fn build(posts: List(post.Post)) {
  sitemap.sitemap(config.root_url() <> "/sitemap.xml")
  |> sitemap.with_sitemap_last_modified(timestamp.system_time())
  |> sitemap.with_sitemap_items([
    sitemap.item(config.root_url() <> "/about.html"),
    sitemap.item(config.root_url() <> "/uses.html"),
    sitemap.item(config.root_url() <> "/contact.html"),
    sitemap.item(config.root_url() <> "/now.html"),
    ..{
      use post <- list.map(posts)
      sitemap.item(config.root_url() <> "/posts/" <> post.slug <> ".html")
    }
  ])
  |> sitemap.to_string()
}
