# Rebuilding the generator

A step by step rewrite of this site's static site generator, in fourteen chapters.

## How to use this

Each chapter is a finished piece of work. You can stop after any of them and
still have a site that builds and deploys. Nothing here asks you to hold a
half-finished refactor in your head overnight.

Every chapter has the same four parts. **The problem** shows you what is wrong
today, with file and line numbers so you can go look. **The idea** explains the
design reasoning, because the point is for you to be able to extend this later
without me. **The work** is what you write. **Check it** is how you know you did
not break anything.

Work them in order. The dependencies are real: chapter 7 cannot happen before
chapter 6, and chapter 6 leans on chapter 5.

## The diagnosis

Three things are wrong at the type level. Almost every other complaint about this
codebase turns out to be one of them wearing a different hat.

**Nothing describes what the build produces.** There is no `Output` type, no
value that answers "which files will this generate". Because that value does not
exist, OG images had to become a side-effecting pass bolted to the bottom of
`main`, link validation has nowhere to live, and `src/build.gleam:91` and `:107`
walk an improvised `[index] ++ pages ++ posts` list three separate times. Adding
a tag index today means editing `main` in three places and remembering the image
pass at the end.

**`Page` is never finished being constructed.** `page.git_hash` and
`page.last_changed_at` shell out to git from inside `common()`, which is a view
function. Rendering one page triggers roughly six `os:cmd` calls, recomputing the
same two facts across `to_elements`, `to_sitemap_item` and `to_feed_item`. You
cannot ask a `Page` when it was last updated. You can only ask the disk.

**The `Renderer(view)` record is the wrong shape.** It has 22 fields, one per
kind of node, and is generic over `view`, which in this codebase is always
`element.Element(Nil)`. Its callbacks receive arguments the dispatch has already
picked apart rather than the node, so some decisions are made before any
renderer is asked, and one of them silently drops footnotes. Overrides work by
record spread, which hides what an override changed. And the two outputs it
serves, the page and the feed, differ less than they should: the feed ships the
site's relative URLs to readers that cannot resolve them.

That one deserves a word of defence for the original. lustre_ssg is a library.
Its consumers are unknown, so handing each callback a pre-digested slice of the
node keeps its API stable whatever jot does next. You are a known consumer with
two known outputs. Copying the library's compromises without the uncertainty
that justified them is how abstractions go stale.

`src/route.gleam` is the counter-example and the model for all of this. Opaque
types, one invariant, one place that enforces it. The rewrite is mostly a matter
of extending that discipline outward.

---

## Chapter 0: Make the ground solid

### The problem

Two things are broken right now, and both will sabotage your ability to verify
anything you do later.

`BLOG_ENV=dev gleam run -m build` crashes. `src/build.gleam:28` points
`drafts_path` at `./drafts`, that directory does not exist, and
`src/page.gleam:68` opens with `let assert Ok(files) =
simplifile.read_directory(path)`:

```
runtime error: let assert
unmatched value: Error(Enoent)
  page.from_folder src/page.gleam:68
  build.main src/build.gleam:55
```

A fresh clone cannot build at all. `.gitignore:11` says `*.typ`, which was meant
for Typst's compiled output but also ignores `src/template.typ`. That file is a
required build input, read at `src/build.gleam:105`. It exists on your machine
and nowhere else.

### The idea

You are about to change a lot of code. The only way to know you have not
quietly broken the site is to compare the output against a known good copy. So
before touching anything structural, get both build modes working and take a
snapshot.

### The work

Make `from_folder` tolerate a missing directory and return an empty list. A
drafts folder that is not there is not an error, it means you have no drafts.

Narrow the gitignore pattern so it catches Typst output without catching Typst
sources. `*.pdf` on line 12 already covers the compiled artefacts, so `*.typ` can
go entirely. Commit `src/template.typ` and `og.typ`.

### Check it

```sh
just build
cp -r priv /tmp/golden

BLOG_ENV=dev gleam run -m build   # no longer crashes
```

From here on, after every chapter:

```sh
just build && diff -r /tmp/golden priv
```

One difference is expected forever: `priv/feed.xml` carries a `<updated>`
timestamp from `timestamp.system_time()`, so it changes on every build. Every
other difference is either a fix you meant to make or a regression you did not.

---

## Chapter 1: Name what the build produces

### The problem

`src/build.gleam` is a script. It interleaves finding content, rendering it, and
writing files, and the writing happens in four different shapes: `create_page`
for HTML, two `write_file` calls for the XML feeds, and `create_image` doing
`simplifile.write_bits` directly. That last one discards its `Result`, so a
failed image write is silent.

### The idea

This is the keystone chapter. Everything later in the book leans on it.

A static site generator does one thing: it turns sources into files. If that is
true, then "a file this build will produce" deserves to be a type. Once it is,
three problems you have been working around just stop existing.

OG images stop being special. Today they are a side effect because there was no
way to say "this build also produces some bytes at this path". With an `Output`
type there is.

Writing to disk collapses to one function. Right now four places know about the
filesystem.

And the set of paths the build emits becomes a value you can hand to something
else. That turns out to be exactly what link checking needs in chapter 12, which
is why that feature has had nowhere to live.

### The work

```gleam
// src/output.gleam

import route

pub type Contents {
  Text(String)
  Bytes(BitArray)
}

pub type Output {
  Output(path: route.Rel, contents: Contents)
}

pub fn write(to out_dir: String, output: Output) -> Nil
```

`write` is the only function in the project that touches the output directory.
It creates parent directories, then writes either a string or a bit array.

Do not restructure `main` yet. Just change the four writing sites to build an
`Output` and hand it to `output.write`. The script is still a script. It now
speaks in one vocabulary.

### Check it

`diff -r /tmp/golden priv` is clean apart from the feed timestamp. You have
changed how the build talks about its output, not what it writes.

---

## Chapter 2: Routes that cannot be wrong

### The problem

`route.rel_page` takes a string and performs four `let assert`s on it:

```gleam
pub fn rel_page(path: String) -> Rel {
  let assert True = string.starts_with(path, "/")
  let assert Ok(uri) = uri.parse(path)
  let assert option.None = uri.scheme
  let assert option.None = uri.host
  Rel(uri, Page)
}
```

Those assertions are honest. They say "I need a root-relative path and I will
crash if you give me something else". But look at who actually calls it.
`page.rel_path` builds the string itself, three lines above, from a slug it
already has. The assertions are checking a string that was constructed correctly
by construction.

Meanwhile `src/layout.gleam:102-106` writes `/`, `/about/`, `/contact/`, `/now/`
and `/uses/` as bare strings, and `:159` writes `/impress.html`, which only
resolves because `caddy/blog.part:23` redirects it. The typed route exists to
make URLs unforgeable, and the file that renders the most URLs forges all of them
by hand.

The feed has the same disease in a worse form. `/feed.xml` is written out by hand
three times: `src/build.gleam:106` for the file the build writes,
`src/feed.gleam:20` for the atom self-link inside that file, and
`src/layout.gleam:63` for the `<link rel="alternate">` that every page carries.
Three spellings of one URL, agreeing by luck. `/sitemap.xml` gets off lighter
with two, `src/build.gleam:98` and `assets/robots.txt:7`, and the second is a
static file the generator only copies, so it stays hand-written.

Hiding in the same file is a worse one. `src/layout.gleam:20` builds the
canonical tag with `html.meta`:

```html
<meta href="https://kevinschweikert.de/uses/" rel="canonical">
```

`rel` is not valid on `<meta>`. Search engines ignore it, so the site has no
canonical tag on any page. The URL in it is correct, trailing slash and all. The
element is not.

### A short detour on trailing slashes

Before fixing anything, it is worth knowing why the site uses `/uses/` rather
than `/uses` or `/uses.html`, because the answer decides what "correct" means for
the rest of this chapter.

Two reasons, both structural rather than cosmetic.

**Relative URLs resolve against a directory.** On `/posts/foo/`, a relative
reference like `img.png` resolves to `/posts/foo/img.png`. On `/posts/foo` it
resolves to `/posts/img.png`, because RFC 3986 drops the last segment. The
trailing slash is what makes the URL behave like a directory. `route.Kind` is
already the encoding of this distinction, and it is the part of the current
design worth protecting.

**A directory containing `index.html` needs no configuration anywhere.** GitHub
Pages, Netlify, Cloudflare Pages, S3 behind CloudFront, nginx, Caddy and
`python -m http.server` all serve it. The extensionless form, where `/uses` is
served from `uses.html`, needs server rewrite rules that do not travel between
hosts.

Modern frameworks increasingly default the other way. Next.js and Astro both
prefer no trailing slash, and it does look cleaner. But they ship an adapter that
owns routing. You deploy static files to a file server, so the portable
convention wins.

So the convention is right and already consistent. What is left are outliers, and
outliers are bugs rather than open questions.

### The idea

An assertion that can never fire is a sign the type is in the wrong place. If
every caller builds the string from a `Route`, then take the `Route`.

Move the route kinds into `route.gleam` so the module owns routing from end to
end. This also clears up a naming collision that has been quietly confusing:
right now there is a module called `route` and a different type called
`page.Route`.

That raises the question of what belongs in `Route`, and the feed is where it
gets interesting. The feed feels like a page. It has a URL, you link to it from
the header, it is a thing the site serves. What it is not is a directory with an
`index.html` inside it.

That distinction is already named, and it is not the one the current API
suggests. `Kind` is not page-versus-asset. It is directory-versus-file: `Page`
gets a trailing slash and `slug/index.html`, `File` gets neither. So the feed is
`Kind.File` and a perfectly good `Route` at the same time. Those are independent
questions, and running them together is what makes `route.asset("/feed.xml")`
read wrong. It is not wrong about the kind. It is wrong about the word.

The temptation now is to drop `Feed` and `Sitemap` into `Route` beside the pages
and move on. Resist it, for a reason that only surfaces one type later. Chapter 5
gives every page a `route` field, so if `Route` can be `Feed`, then a page whose
route is the feed type-checks, and so does asking that feed for the social card
it does not have. You would spend this chapter deleting assertions that cannot
fire and hand back an `Option` that is always `Some` on the way out.

So split the question in two. A `Route` is a page, and that is all it ever is. A
`Target` is anything the build emits a URL for, and a page is one of the things
it can be. The social card is another, and that is what makes the split pay: an
OG image is a file derived from a page, so `Target` carries the `Route` it
belongs to, and the derivation stops being an outlier bolted to the side.

Variants rather than functions, and the reason is worth stating. A `route.feed()`
returning a `Rel` would spell the URL once, which is most of the win, but it
hands back a value nothing can enumerate. A variant is a member of a set you can
list, and listing that set is what chapter 8's `Targets` and chapter 12's
validator are for. The header links to `/feed.xml` from every page on the site,
so chapter 12 has to know that URL is real. `Target` tells it, and tells it about
the OG images too, which a function on `Route` would have left outside the set.

### The work

```gleam
// src/route.gleam

/// A page the site serves as a directory with an index.html in it.
pub type Route {
  Home
  Standalone(slug: String)
  Article(slug: String)
}

/// Every file the build emits a URL for.
pub type Target {
  Document(Route)
  OgImage(Route)
  Feed
  Sitemap
}

/// Total.
pub fn target(target: Target) -> Rel

/// Total. Linking only ever points at pages, so this is what the views use.
pub fn of(route: Route) -> Rel

/// Total. Every page has a social card.
pub fn og_image(route: Route) -> Rel

/// Total. Asset paths come from walking assets/, so they are known good.
pub fn asset(path: String) -> Rel
```

`Site(slug)` becomes `Standalone(slug)`, because in chapter 5 `Site` starts
meaning the whole site.

`of` and `og_image` are one-liners over `target`, `Document(route)` and
`OgImage(route)` respectively. They earn their place because there are two
audiences here and they want different things. Views link, and a link only ever
points at a page. Generators emit, and they need the whole set. Keeping both
doors open means the nav never writes `Document` and chapter 8 never writes a
special case.

`Document` and not `Page` as the variant name, because chapter 5 introduces
`site.Page` and the book already flags one collision of this shape, a module
called `route` next to a type called `page.Route`. No sense recreating it
mirrored.

Note what happens to `Kind`. Today `rel_page` and `rel_file` ask the caller to
pick. Now `target` picks, and it is the only thing that does: `Page` for
`Document`, `File` for `OgImage`, `Feed` and `Sitemap`. An asset is always a
file. Nothing outside the module can get it wrong, and `rel_page` and `rel_file`
become private.

`page.stem` at `src/page.gleam:152` dissolves rather than moving. It exists only
to build the OG image path at `:179`, and that path is a function of the route,
so `OgImage` derives it and `stem` stops being a concept worth having. Note what
`og_image` does not return. There is no `Option`, because a `Route` is a page and
every page has a card. The `Option` in today's `page.og_image_url` survives only
to serve `page.Image`, which chapter 5 deletes as dead, and both call sites,
`src/layout.gleam:82` and `src/build.gleam:127`, already know they are holding a
page.

Derive the image path from the document path rather than from a hand-rolled
stem. `og-` plus a flattened slug is how it works today, and the flattening is
not quite safe: `Standalone("post-foo")` and `Article("foo")` both land on
`og-post-foo.png`. Nothing collides right now, but the `post-` prefix is a
convention doing a type's job. The document path is already unique per route, so
reuse it. `/about` becomes `/images/og/about.png`, `/posts/foo` becomes
`/images/og/posts/foo.png`. Collisions stop being unlikely and start being
impossible, and the generated cards move out of `images/`, where they currently
sit interleaved with the files copied from `assets/images/`.

This renames all eight cards, so the old `/images/og-*.png` URLs 404. The
`og:image` tag platforms read is correct, so what breaks is previews cached
elsewhere from before. The reason to do it in this chapter rather than later: the
paths are one private function with no call sites to chase.

Delete `fs_abs_path` and `abs_from_base`. Neither has a caller.

Then fix the layout. Nav entries come from `route.of(Standalone("about"))` and
friends, so the layout cannot name a page that does not exist, and the footer's
`/impress.html` becomes `/impress/` as a consequence rather than as a patch. The
feed link at `:63` becomes `route.target(Feed)`, and so do `src/feed.gleam:20`
and `src/build.gleam:106`. `src/build.gleam:98` becomes `route.target(Sitemap)`.
Four hand-written paths, one spelling each, all of it in `route.gleam`.

Change `html.meta` to `html.link` on line 20 while you are in the file. One word,
and it is the difference between having canonical tags and not.

Two links in content point at the non-canonical form. Fix them here, because
chapter 12 will reject them and you would rather meet them now than as a wall of
validator output later:

- `posts/build-home-assistant-devices-with-elixir-and-nerves.dj:485` links to
  `/contact.html`
- `pages/now.dj:9` links to `/uses#Camera`, which needs `/uses/#Camera`

### Check it

```sh
rg -o '<link[^>]*canonical[^>]*>' priv/index.html priv/*/index.html
```

One hit per page, each a `<link>`, each with a trailing slash. No `<meta>` tag
anywhere should carry a `rel` attribute.

```sh
rg -n 'feed\.xml|sitemap\.xml' src/
```

Two hits, both in `route.gleam`, both inside `target`. Anything else is a path
that can still drift.

The diff shows five things and no sixth. The canonical tags change element on all
eight pages. `/impress.html` becomes `/impress/` in every footer.
`/contact.html` and `/uses#Camera` pick up their slashes, the first of them
twice, because the feed carries a pre-rendered copy of that post. The `og:image`
URLs move to `/images/og/...` and the eight PNGs underneath them are renamed. And
`feed.xml` carries its usual new timestamp.

`sitemap.xml` is byte-identical, which is the feed and sitemap work reporting in:
three spellings that agreed by luck now agree by construction, and agreeing by
construction looks like nothing at all. The site also stops depending on Caddy
redirects for its own links.

### What the server already does

Worth knowing, because it tells you what these fixes are and are not for. Against
the local `:8080` Caddyfile, every non-canonical form already redirects:

```
/uses                            308 -> /uses/
/uses.html                       308 -> /uses/
/uses/index.html                 308 -> /uses/
/index.html                      308 -> /
/contact.html                    308 -> /contact/
/posts/composable-sftp-streams   308 -> /posts/composable-sftp-streams/
/nope                            404
```

All permanent, all single hop, no duplicate content anywhere. Note that `/uses`
redirects even though `caddy/blog.part` has no rule for it: the explicit rules
only cover `.html` suffixes, and the bare directory case comes from Caddy's
`file_server`, which canonicalizes a directory request that arrives without a
trailing slash. nginx does the same. That behaviour is portable, not bespoke
config.

So nothing on the site is actually broken by the non-canonical links. Fix them
anyway, for two reasons that are smaller but real. Every visitor who follows the
footer link pays an extra round trip, and crawlers spend their budget walking
redirects instead of pages.

The canonical tag is the one that was genuinely not working, and redirects do not
cover for it. A redirect fires on a path; a canonical tag also settles query
strings like `?utm_source=`, the apex versus `www` variant, and any host the site
is ever mirrored on. Right now the element claims to do that job and does none of
it.

---

## Chapter 3: Configuration is data

### The problem

`src/config.gleam` is four functions returning constants. `root_url()` parses a
URI from a string every time it is called, and it is called once per route
conversion.

The real cost is not the parsing. It is that the base URL is compiled in, so you
cannot build a copy of the site at a different address. No staging deploy, no
local preview with absolute URLs that work, no way to check what the generator
would do for a different domain.

### The idea

Configuration that never changes is still configuration. Make it a value, pass
it where it is needed. This is a small chapter and a quiet one, but it is what
makes chapter 8's generators take a `Site` rather than reaching for globals.

### The work

```gleam
// src/config.gleam

pub type Config {
  Config(
    base: uri.Uri,
    title: String,
    description: String,
    author: String,
    repo: String,
  )
}

pub fn default() -> Config
```

`title` and `description` come from `src/index.gleam:15,17`, where they are
currently the home page's constants. This is where they become the site's.
`domain()` disappears into `base.host`.

`route.abs` currently calls `config.root_url()` internally. It now takes the base
as an argument instead. That is slightly more typing at each call site and much
more honest: converting a relative route to an absolute one genuinely does depend
on where the site lives. Notice what it does to the import graph. `route.gleam`
drops its `config` import and ends the chapter depending on nothing in this
project at all, which is a fair description of what a routing module should be.

Then make something produce a config that is not the default, because otherwise
the capability this chapter opens by promising does not exist and `default` is a
name for a thing with no alternative. The environment is the obvious source, and
`src/build.gleam:37` already reads `BLOG_ENV` this way:

```gleam
let config = case envoy.get("SITE_URL") {
  Ok(url) -> {
    let assert Ok(base) = uri.parse(url)
    config.Config(..config.default(), base:)
  }
  Error(_) -> config.default()
}
```

Reading it here rather than inside `config.default()` keeps `config.gleam` free
of I/O, which is the same boundary discipline chapter 4 is about to argue for at
greater length.

One small fix falls out while you are in `feed.gleam`. Lines 15 and 16 use
`config.domain()` for both the atom title and the atom id, and those want
different things: the title is `config.title`, the id is the base URL.

### Check it

```sh
just build && diff -r /tmp/golden priv
```

Clean apart from the feed timestamp. Then try the capability:

```sh
SITE_URL=http://localhost:8080 just build
rg -o 'https?://[^<]*' priv/sitemap.xml | head -3
```

Local URLs in `sitemap.xml` and `feed.xml`, and the canonical tags and `og:image`
in every page pointing at `localhost` too. That is the whole point of the
chapter, and it is now one environment variable rather than an edit and a
rebuild.

---

## Chapter 4: Finish constructing the page

### The problem

Here is `common()`, from `src/page.gleam:181`, which runs for every page:

```gleam
case git_hash(page.src) {
  option.Some(hash) -> { ... }
  option.None -> element.fragment([])
}
```

`git_hash` runs `os:cmd("git rev-list -1 HEAD -- " ++ Path)`. So does
`last_changed_at`, with a different command. `common()` calls both. It is called
by `to_elements` for the page, and again by `to_minimal_elements` for the feed.
`to_sitemap_item` calls `updated_date` a third time.

That is around six shell invocations per page, recomputing two unchanging facts,
from inside view code.

There is a second bug hiding in `src/git_ffi.erl:14`. The path is interpolated
into a shell string with no quoting.

### The idea

Rendering should be a pure function from a value to markup. If rendering shells
out, it is not reproducible, it is not testable without a git repository, and it
is slow in a way that scales with the number of pages times the number of output
formats.

The fix is to resolve git facts once, when you first read the file, and store
them. A `Page` should be a complete answer, not a promise to go find out.

This is the "parse, don't validate" idea applied to I/O. Do the uncertain work at
the boundary, once, and hand the rest of the program something certain.

Something is in the way of that, and it is why this chapter is harder than it
reads. `page.Source` is two types sharing a name. Count the functions that match
on it. `git_hash` at `src/page.gleam:113` and `last_changed_at` at `:124`
destructure it to reach a file path. `render` at `:234` and `render_minimal` at
`:241` destructure it to reach a body. Nothing uses both halves.

That is the split line, and it is already drawn in your own code. The provenance
half is what this chapter needs and it becomes `Source`. The body half is what
chapter 5 needs and it becomes `Body`. Do the rename here rather than there, so
the old name and the new one never exist at the same time, and so chapter 5 is
left changing only what the variants hold.

### The work

```gleam
// src/content.gleam

pub type Revision {
  Revision(hash: String, changed_at: calendar.Date)
}

/// Where a document came from, and what git knows about it.
/// Resolved once at discovery. Rendering never touches the filesystem.
pub type Source {
  Source(path: String, revision: Option(Revision))
}

pub type Body {
  Djot(content: String)
  Elements(List(element.Element(Nil)))
}

pub type Page {
  Page(
    route: route.Route,
    published: calendar.Date,
    meta: Meta,
    source: Option(Source),
    body: Body,
  )
}
```

`Meta` moves across unchanged. Chapter 3 already took `author` off it, and
chapter 5 takes `image`, so this chapter has no business with it.

Notice what the old variants lose. `Djot` gives up `path` and `Elements` gives up
`origin_path`, because both of those were provenance wearing a body's clothes.
They move into `Source`, which is the whole point of the split: there was one
idea, "the file this came from, maybe", spelled two different ways depending on
which variant you were holding.

The two `Option`s are not one `Option` in disguise, and it is worth being
deliberate about keeping them apart. `source: None` means there is no file behind
this page at all, which is what chapter 5's computed pages will be.
`Some(Source(path, revision: None))` means there is a file and git has never seen
it. That second case is live today: `git.full_hash` fails on an untracked file
and `option.from_result` quietly turns it into `None`, which is how a draft you
have not committed renders without a commit link. Flatten the two and you lose
the ability to tell a page with no file from a file with no history.

Discovery resolves the `Revision` once, with one `git.full_hash` and one
`git.last_changed_at` per file, and stores it. `build.gleam`'s hand-built index
page gets a `Source` too, pointing at `./src/index.gleam`.

Then three things fall out. `git_hash/1` and `last_changed_at/1` delete outright.
`updated_date` stops taking a `Page` so it can go and ask the disk, and becomes a
comparison between two dates it is handed. `common()` reads a field.

While you are in the FFI, quote the path.

### Check it

```sh
# before and after, on the same content
time just build
```

The build currently takes about a second, most of it process spawning. Expect
that to drop. More importantly, rendering is now a pure function, which is what
makes chapter 13's tests possible.

The diff should be clean apart from the feed timestamp. Two unchanging facts
computed once instead of six times are still the same two facts.

---

## Chapter 5: A model of the site

### The problem

The home page is built by hand in `src/build.gleam:66-82`, with a date typed
directly into the source:

```gleam
let index =
  page.Page(
    route: page.Home,
    published: calendar.Date(2026, calendar.January, 18),
    src: page.Elements(index.view(posts), origin_path: option.Some(index_path)),
    ...
  )
```

It needs this treatment because its content depends on the other pages. You
cannot build it during discovery, because during discovery you do not yet know
what the articles are.

So `page.Source` grew an `Elements` variant to hold pre-rendered Lustre elements,
and `main` grew a special case. Any future page with the same shape, a tag index,
a yearly archive, needs another special case.

### The idea

The home page is not a document. It is a view over the collection of documents.
Once you say that out loud, the type writes itself: its body is a function from
the site to elements.

```gleam
pub type Body {
  Djot(jot.Document)
  Computed(fn(Site) -> List(element.Element(Nil)))
}
```

Now the home page is an ordinary page. So is a tag index, so is an archive. The
special case dissolves rather than moving somewhere else, which is the difference
between a fix and a refactor.

Notice also that `Djot` holds a parsed `jot.Document`, not a raw string. Today
`page.render` and `page.render_minimal` each call `jot.parse` on the same text,
so every post is parsed twice. Parsing at discovery means it happens once, and it
means the link checker in chapter 12 reads exactly the same tree the renderer
does, rather than a second parse that might drift.

### The work

```gleam
// src/site.gleam

pub type Site {
  Site(config: Config, pages: List(Page))
}

pub type Page {
  Page(
    route: route.Route,
    published: calendar.Date,
    meta: content.Meta,
    source: Option(content.Source),
    body: Body,
  )
}
```

`source` is `Option` because a computed page may have no file behind it.

`route` is a `route.Route` and not a `route.Target`, which is the whole point of
the split chapter 2 made. A `Page` cannot be the feed. Nothing in this type needs
to defend against it and no function that takes a `Page` has to wonder.

Three types go away here. `page.Image` has three variants and only one is ever
constructed: `extract_meta` at `src/page.gleam:109` hardcodes `Generated`, so
`None` and `File(url:)` are dead. Chapter 2 already made the OG image path a
total function of the route, so deleting `Image` takes `page.og_image_url` with
it and its two callers go straight to `route.og_image`, which hands back a `Rel`
rather than an `Option` they would only have to unwrap.

`page.SitemapItem` and `page.FeedItem` also go. They are projections, and
projections do not need types. `FeedItem` is the worse of the two: it carries a
pre-rendered `html: String` field, which means rendering happens during what
looks like a data conversion.

### Check it

`index.gleam` becomes `view/home.gleam` and returns a function rather than being
called eagerly. The hardcoded January 2026 date disappears, replaced by the git
revision of the view file itself. Expect that one date to change in the diff.

---

## Chapter 6: A visitor the right shape

### The problem

`src/djot.gleam` is lustre_ssg's renderer, copied in: a `Renderer(view)` record
with 22 fields, one per kind of node, generic over `view`. `site.styled_renderer`
at `src/site.gleam:184` builds one as
`Renderer(..default_renderer(), codeblock: ..., image: ...)`, and the feed uses
`default_renderer()` as it is. The dead `src/render.gleam` holds a third, with
its `codeblock` override commented out.

The visitor itself is the right idea. You want to decide how each kind of node
becomes markup, and you have two outputs that decide differently. Three details
of this particular visitor get in the way.

The callbacks receive arguments the dispatch has already chewed. `link` gets an
`Option(String)`, a dict and some children, never the node. `span`, `insert`,
`delete` and `mark` get their content flattened to a `String`, so formatting
inside them is gone before any renderer sees it. Some nodes never reach a
callback at all. `src/djot.gleam:381` turns `jot.Footnote(_)` into
`renderer.text("")` and `:202` throws away the document's `footnotes`.
`pages/uses.dj:11` uses a footnote that `:50` defines, so "KVM stands for
Keyboard, Video and Mouse" never reaches the page. No renderer can fix that,
because the decision was made before any renderer was asked.

Overrides work by record spread. `..default_renderer()` quietly fills every field
you did not name, so the only way to see how the browser differs from the feed
is to diff two record literals in your head. The commented-out field in
`render.gleam` is what that looks like after a while.

The recursion lives in the dispatch. That is why `render_block` and
`render_inline` pass `references, reference_attributes, renderer` into every
call, and why each arm runs to fifteen lines.

Then there is the feed. Feed content is read in someone else's app, which has no
base URL and never loads your stylesheet. Today it gets the same relative URLs
as the site, three of them: `/files/composable-sftp-streams.livemd`,
`/images/ha_my_switch.png` and `/contact/`. A reader resolves those against the
wrong host or not at all. It also carries inline list styles, `data-*`
attributes and class hooks that mean nothing outside your CSS.

Two smaller bugs ride along. `src/djot.gleam:181` prepends `attribute.class(class)`
to attributes jot has already given that class, so `::: info` renders as
`<div class="info info">`. And `:77` passes the code fence language through as
written while glimra lowercases it, so a `JSON` fence would get different
`data-lang` values on the page and in the feed.

### The idea

Keep the visitor and change its shape. Two fields, one per node family, and
each one receives the node itself:

```gleam
// src/djot/render.gleam

pub type Renderer {
  Renderer(
    block: fn(Block, Context) -> Element(Nil),
    inline: fn(Inline, Context) -> Element(Nil),
  )
}

pub opaque type Context {
  Context(renderer: Renderer)
}
```

`Block` and `Inline` are this module's own types, not `jot.Container` and
`jot.Inline`. That is the one addition this chapter makes beyond handing a
renderer the node as-is, and it is worth being honest about why: the first cut
of this design tried to get away with reusing jot's types directly, resolving
destinations and footnote keys as a side effect of traversal, and it broke the
same way twice.

The first crack was `jot.Destination`. A `Link` or `Image` whose destination had
already been resolved was still typed `jot.Destination`, which has two
constructors, `Url` and `Reference`. Nothing stopped an override from matching
`Reference` and doing something with it, or from being written against a
destination that was never resolved in the first place, because the type could
not tell the difference between "resolved" and "not resolved". The only honest
fix available with jot's own type was `let assert jot.Url(url) = destination` at
every call site that needed the URL, a loud trust boundary rather than a silent
one, but still a value every override had to independently remember to narrow.

The second crack was worse, because it was not about one field, it was about an
entire convention. A footnote reference and its endnote need to agree on an id
scheme, and "agree" meant two separate pieces of code each formatting a string
with the same prefix. A function shared between them, `footnote_anchor(key)`,
only narrows the problem: it is still something a call site can choose not to
call. Nothing in `jot.Inline`'s shape makes a mismatched id unrepresentable.

Both cracks have the same shape: a renderer was being handed raw material and
trusted to process it correctly, when the processing was not a rendering
decision at all, it was referential integrity. The fix is the one this book
already uses for I/O in chapter 4, applied to djot's own indirections. Resolve
every `Destination` and every footnote key exactly once, at a boundary, into a
type that has no constructor for the unresolved state:

```gleam
pub type Block {
  ThematicBreak
  Paragraph(attributes: Dict(String, String), content: List(Inline))
  Heading(attributes: Dict(String, String), level: Int, content: List(Inline))
  Codeblock(attributes: Dict(String, String), language: Option(String), content: String)
  RawBlock(content: String)
  BulletList(layout: jot.ListLayout, style: jot.BulletStyle, items: List(List(Block)))
  OrderedList(
    layout: jot.ListLayout,
    punctuation: jot.OrdinalPunctuation,
    ordinal: jot.OrdinalStyle,
    start: Int,
    items: List(List(Block)),
  )
  BlockQuote(attributes: Dict(String, String), items: List(Block))
  Div(attributes: Dict(String, String), items: List(Block))
  Footnotes(entries: List(FootnoteEntry))
}

pub type FootnoteEntry {
  FootnoteEntry(note_id: String, label: String, content: List(Block))
}

pub type Inline {
  Linebreak
  NonBreakingSpace
  Text(String)
  Link(attributes: Dict(String, String), content: List(Inline), url: String)
  Image(attributes: Dict(String, String), content: List(Inline), url: String)
  Span(attributes: Dict(String, String), content: List(Inline))
  Emphasis(content: List(Inline))
  Strong(content: List(Inline))
  Delete(content: List(Inline))
  Insert(content: List(Inline))
  Mark(content: List(Inline))
  Footnote(label: String, ref_id: String, note_id: String)
  Code(content: String)
  MathInline(content: String)
  MathDisplay(content: String)
  Symbol(content: String)
}
```

`Link.url` and `Image.url` are bare `String`s. There is no `Reference`
constructor anywhere in sight of a renderer, so there is nothing to narrow and
nothing to forget to narrow. `Inline.Footnote` carries exactly the three
strings a renderer needs, `label`, `ref_id`, `note_id`, already matched to
whatever `Block.Footnotes` built for the same key, because both come from one
computation, done once, not two independently-written ones that happen to agree
today.

That split, resolve once versus render repeatedly, is also why `Context` loses
its `doc` field. The only reason it held the document before was to resolve
references and footnote keys on demand, during traversal. Once that work moves
to a separate pass that runs before any `Renderer` exists, `Context` has nothing
left to do but carry the current `Renderer` along for recursion.

Three things follow from `Block`/`Inline` carrying only resolved state.

A renderer gets the node, so every decision belongs to the renderer. Nothing is
left for a dispatch to decide on its behalf, and a footnote cannot get lost
before anyone is asked about it, nor can it get a different id than the one its
own endnote uses.

Children render through the context, and the context renders through the
current renderer. `render.blocks(ctx, items)` calls `ctx.renderer.block` on each
item. This is open recursion, and it is what makes an override hold at every
depth: when you render the feed, a code block inside a `::: tip` gets the feed's
treatment without the feed saying anything about divs. `Footnotes` is an
ordinary block under this same recursion, not a special case bolted onto the
traversal: an output can override how the endnotes section looks, or drop it
entirely, exactly as it would override `Div`.

Overriding is a `case` with a fallback. The standard rendering is two plain
functions in `djot/html.gleam`, exhaustive over every variant. An output matches
the cases it cares about and hands the rest to `djot_html.block` or
`djot_html.inline`. One function tells you exactly how an output differs from the
standard, and the compiler keeps the standard exhaustive. Compare that with a
spread, which tells you nothing.

That gives you two ways to override, and both are ordinary functions. You can
replace the output for a case, which is what the browser does for code blocks
and images. Or you can rewrite the node and then delegate, which is what the
feed does: it makes a `Link` or `Image`'s `url` absolute, then lets the standard
rendering build the `<a>` and `<img>` it would have built anyway.

There is no `view` parameter. Every output here is `Element(Nil)`, and a type
parameter with one instantiation is a promise to a consumer who does not exist.

There are two fields, `block` and `inline`, rather than one, and it is worth
being precise about why that stays true even now that both are this module's
own types rather than jot's. Containers and inlines are genuinely different
grammars: a `Paragraph` can never appear where an `Inline` is expected, and a
`Link` can never hold a `Paragraph` as a child. That is enforced today for free,
by `content: List(Inline)` versus `items: List(Block)`, with no runtime check
anywhere. A single `Node` type covering both would need every such field to be
`List(Node)`, which makes that illegal nesting representable even though it can
never actually happen, trading away a real guarantee for a shorter type
definition. The footnote split shows exactly where this bites: a footnote
reference carries no content at all, just three strings, while a footnote's
definition is genuinely block content, jot stores it as `List(Container)` since
a footnote can hold paragraphs or lists. Keeping `Block` and `Inline` separate
is what lets `FootnoteEntry.content: List(Block)` and `Inline.Footnote`'s empty
hands say that out loud, in the type, rather than leaving it as something only
the author of the next renderer is expected to know.

The API grows in two directions, both cheap. A third output, say an email
newsletter, is another `Renderer` value with its own overrides. A change every
output should get goes in `djot/html.gleam` once. A decision no output wants
differently yet becomes a new field on `Renderer` the day one actually does, and
the compiler then points at every `Renderer(...)` that has to supply it.

glimra ends up named in exactly one place, the browser's code block override.
That is what makes the alternatives at the end of this book a one-function
change. Its grammar list covers bash, c, css, elixir, erlang, gleam, go, html,
javascript, json, python and rust, which is why your `iex` block is not
highlighted today.

### The work

Five pieces, in this order, each one checked against the golden copy before you
start the next. The order matters. If the diff after a step shows anything it
should not, you know which step caused it.

**Step 1: resolve.**

`src/djot/render.gleam` gains a pass that runs before any `Renderer` exists and
never touches one. It is the only code in the project that imports
`jot.Destination`'s constructors, and the only code that ever reads
`doc.references`, `doc.reference_attributes` or `doc.footnotes`.

```gleam
pub fn document(doc: jot.Document) -> List(Block)
```

Walking `doc.content`, it turns every `jot.Container` into a `Block` and every
`jot.Inline` into an `Inline`. Most variants carry straight across unchanged.
Three do not.

A `jot.Link` or `jot.Image`'s `destination` gets resolved and folded into
`url: String`. A `jot.Url` resolves to itself with no attributes added. A
`jot.Reference` looks up both reference dicts, merges the reference's
attributes into the node's own (node's own on the left of `dict.merge`, so the
diff stays clean), and the result becomes the node's `url`. A definition like

```djot
{title="The Gleam language"}
[gleam]: https://gleam.run
```

gives every `[...][gleam]` link its URL and its `title`, and no renderer ever
sees that a reference was involved. No document uses that today, and it stays
supported anyway: the standard rendering supports the whole of djot, not just
the parts this site happens to use, so a post you write next year can use any
of it without a trip back into the renderer. If a key is not found, that is
exactly what chapter 12's validator exists to catch before this code ever runs;
leave the `url` as the original reference text in that case rather than
crashing, so a document with no validator in front of it yet still renders
instead of halting the build.

`jot.Div`'s separate `class` field is dropped, folded into `attributes` the one
time this pass runs over it. jot has already merged `class` into the
attributes dict itself (`build/packages/jot/src/jot.gleam:622`), so once this
conversion happens exactly once there is no second copy left anywhere for a
renderer to read and double.

A `jot.Footnote(reference)` and a `jot.Document`'s `footnotes` dict both come
from one pass over `doc.footnotes`' keys, built once:

```gleam
type Anchor {
  Anchor(label: String, ref_id: String, note_id: String)
}

fn anchors(footnotes: Dict(String, List(jot.Container))) -> Dict(String, Anchor) {
  use key <- dict.map_values(footnotes)
  let assert "^" <> label = key
  Anchor(label:, ref_id: "fnref-" <> label, note_id: "fn-" <> label)
}
```

Both jot's inline footnote reference and its definition key are seeded by jot
itself with a leading `"^"` (`build/packages/jot/src/jot.gleam:1289` for the
reference, `:435` for the definition), so a raw key reads `"^kvm"`, not `"kvm"`.
This is where that gets stripped, once; nothing downstream needs to know jot
does this.

Every `jot.Footnote(reference)` becomes `Inline.Footnote(label:, ref_id:,
note_id:)` by looking itself up in that same `anchors` dict, and the resolve
pass appends one `Block.Footnotes(entries:)` built from the same dict, in
sorted-key order, when `doc.footnotes` is non-empty. The inline reference and
the endnote read the identical computed value; neither recomputes the id
scheme, because there is no second place left that knows what the scheme is.

**Step 2: traversal and the standard rendering.**

```gleam
pub fn blocks(ctx: Context, nodes: List(Block)) -> List(Element(Nil))
pub fn inlines(ctx: Context, nodes: List(Inline)) -> List(Element(Nil))
```

Both are now pure dispatch, nothing else: `ctx.renderer.block`/`ctx.renderer.inline`
on each node, no destination to resolve, no dict to consult, because step 1
already did that work. This is also why `Context` only carries a `Renderer`
now.

`src/djot/html.gleam` is what djot means in plain HTML. It handles every
variant of `Block` and `Inline`, passes author attributes through, and adds no
CSS hooks. Import lustre's module as `lustre/element/html as h` to avoid the
name clash.

```gleam
pub fn renderer() -> Renderer { Renderer(block:, inline:) }

pub fn block(node: Block, ctx: Context) -> Element(Nil) {
  case node {
    Paragraph(a, content) -> h.p(attributes(a), render.inlines(ctx, content))
    BlockQuote(a, items) -> h.blockquote(attributes(a), render.blocks(ctx, items))
    Div(attributes: a, items:) -> h.div(attributes(a), render.blocks(ctx, items))
    Codeblock(a, _, source) -> h.pre(attributes(a), [h.code([], [h.text(source)])])
    Footnotes(entries:) -> h.text("")
    // ...
  }
}
```

The rest of the standard rendering, so nothing gets dropped on the way:

- `Span`, `Insert`, `Delete` and `Mark` render their children through
  `render.inlines`. Today they flatten to a string, so `{=*very*=}` loses its
  bold.
- Bullet lists are a plain `<ul>`. Ordered lists are an `<ol>` with `start` when
  it is not 1, and `type="a"` or `type="A"` for alphabetic ordinals. HTML has no
  attribute for the `1)` versus `1.` punctuation, so it renders as a plain list.
  Loose lists wrap each item's content in `<p>`, tight ones do not.
- Inline and display math keep the `math inline` and `math display` classes
  around `\(...\)` and `\[...\]`. Those classes are djot's convention for MathJax
  and KaTeX, not a hook into your CSS, so they belong in the standard.
- A symbol like `:smile:` renders literally, as `:smile:`. That is djot's
  default, and today's renderer gets it wrong by dropping the colons.
- Raw `=html` blocks go through `element.unsafe_raw_html`, the way they do
  today.

Leave `Inline.Footnote` and `Block.Footnotes` as stubs (`h.text("")`) for now,
which is today's behaviour (a footnote currently vanishes). Step 5 is where
they change. The type already carries the real fields either way, since
`document` from step 1 has to produce them; only the markup is deferred.

Keep the old `to_attributes` exactly as it is. It folds the dict in a particular
order, and a new order would flood the diff with attribute reshuffles.

Nothing uses these modules yet, so there is nothing to diff. `gleam build` is the
check.

**Step 3: the browser.**

Replace `styled_renderer` in `src/site.gleam` with `browser()` and point
`render` at `render.document(doc) |> render.render(browser(), _)` (or
equivalent):

```gleam
pub fn browser() -> render.Renderer {
  render.Renderer(
    block: fn(node, ctx) {
      case node {
        render.Codeblock(a, language, source) -> highlighted(a, language, source)
        render.BulletList(..) | render.OrderedList(..) -> styled_list(node, ctx)
        _ -> djot_html.block(node, ctx)
      }
    },
    inline: fn(node, ctx) {
      case node {
        render.Image(..) -> figure(node, ctx)
        _ -> djot_html.inline(node, ctx)
      }
    },
  )
}
```

`highlighted` is the body of today's `codeblock` override. Lowercase the language
first, once, and that is the third bug gone. `styled_list` keeps the inline
`list-style-type` and `data-punctuation` the page has today, for both kinds of
list. `figure` is today's image override. Its `url` is already resolved by the
time it runs, since step 1 folded the destination into a plain `String` before
any renderer existed, so `figure` only has to pattern-match
`render.Image(attributes, content, url)` and build the `<figure>`. There is no
`jot.Url` to destructure and no case to make for a `Reference` that cannot
appear.

Math, symbols and the inline formatting fall through to the standard rendering.
Symbols are the one place the browser's output changes in principle, gaining
their colons back, but no page uses one, so the diff stays quiet.

`render_minimal` stays on the old `djot.default_renderer()` for one more step.

**Step 4: the feed.**

```gleam
pub fn feed(page: uri.Uri) -> render.Renderer {
  render.Renderer(
    block: fn(node, ctx) { djot_html.block(strip_block(node), ctx) },
    inline: fn(node, ctx) {
      djot_html.inline(node |> absolutize(page) |> strip_inline, ctx)
    },
  )
}
```

`strip_block` empties the attributes of `Paragraph`, `Heading`, `Codeblock`,
`BlockQuote` and `Div`. `strip_inline` does the same for `Link`, `Image` and
`Span`. `absolutize` has a smaller job than it would have had before step 1
started resolving destinations itself: a `Link` or `Image` reaching `feed`'s
`inline` callback already carries a plain `url: String`, reference attributes
already merged in, so `absolutize` only rewrites that string against the page
and puts it back, no destination type involved at all:

```gleam
fn absolutize(node: render.Inline, page: uri.Uri) -> render.Inline {
  case node {
    render.Link(attributes:, content:, url:) ->
      render.Link(attributes:, content:, url: absolute(url, page))
    render.Image(attributes:, content:, url:) ->
      render.Image(attributes:, content:, url: absolute(url, page))
    _ -> node
  }
}

fn absolute(url: String, page: uri.Uri) -> String {
  {
    use parsed <- result.try(uri.parse(url))
    use merged <- result.try(uri.merge(page, parsed))
    Ok(uri.to_string(merged))
  }
  |> result.unwrap(url)
}
```

Merge against the page, not the site base. RFC 3986 then handles every case with
no special code, `/contact/` resolves against the host, `#frag` becomes the
page's own URL plus the fragment, and `https://` or `mailto:` come back
unchanged — with one exception `gleam_stdlib` does not get right. `uri.merge`'s
`remove_dot_segments` (`gleam/uri.gleam:605-626`) treats every empty path
segment as a dot-segment to discard, the same as `"."`, instead of only
discarding `"."` and `".."`. A trailing slash on an absolute-path reference
splits into a trailing empty segment, so `/contact/` merges down to `/contact`,
regardless of what the base path looks like. Restore it by hand:

```gleam
let path = case
  string.ends_with(parsed.path, "/") && !string.ends_with(merged.path, "/")
{
  True -> merged.path <> "/"
  False -> merged.path
}
Ok(uri.to_string(uri.Uri(..merged, path:)))
```

This is where chapter 2's trailing-slash detour pays off regardless: `route.Abs`
stores the path without the slash and adds it in `abs_string`, so merging
against the stored URI would resolve `img.png` on `/posts/foo/` into
`/posts/img.png`. Add `route.abs_uri(abs) -> uri.Uri` returning the canonical
form, rewrite `abs_string` as `abs_uri` piped into `uri.to_string`, and pass
`abs_uri` of `site.abs_path(page, base)` to `feed`. That means
`to_minimal_elements` hands the page to `render_minimal` rather than only its
body.

With both outputs on the new modules, delete `src/djot.gleam` and
`src/render.gleam`. `gleam build` should be warning-clean.

**Step 5: footnotes.**

Replace the two stub arms left in step 2. `Inline.Footnote(label:, ref_id:,
note_id:)` renders `<sup><a id={ref_id} href="#{note_id}">{label}</a></sup>`.
`Block.Footnotes(entries:)` renders `<section role="doc-endnotes">` with an
`<ol>`; each `<li id={entry.note_id}>` holds `{entry.label}: ` followed by the
footnote's blocks rendered through `render.blocks`, which means through the
current renderer. When `doc.footnotes` was empty, step 1 never appended a
`Footnotes` block at all, so there is nothing here to special-case for that.

`label` is the footnote's own key, sorted alphabetically for entry order, since
nothing upstream tracks order of first reference the way jot's own HTML output
does by threading state through every call
(`build/packages/jot/src/jot.gleam:2861`). The cost is that writing `[^b]`
before `[^a]` on one page orders them the other way around. There is one
footnote on the whole site. If you want numbered footnotes instead of named
ones, or if the ordering ever bites, change `label` where step 1 builds the
`anchors` dict; neither `Inline.Footnote` nor `Block.Footnotes` has to change,
because both only ever read whatever `label` is in effect.

### Check it

After step 3 (the browser):

```sh
just build && diff -r /tmp/golden priv
```

Ten callouts lose their doubled class, across the two posts and `/uses/`:
`class="info info"`, `"tip tip"` and `"note note"` each become a single class.
Every other page is byte-identical. Any other difference means the port is not
faithful, so look at attribute order first.

After step 4 (the feed), `feed.xml` changes and nothing else does. Every `href`
and `src` in the entries starts with `https://kevinschweikert.de/`, trailing
slashes included — check `/contact/` specifically, since that is the one the
`uri.merge` workaround exists for. The `class`, `style` and `data-*` attributes
are gone. Code blocks are a bare `<pre><code>`, and images are a bare `<img>`,
without the browser's `<figure>`.

```sh
rg -c 'href=&quot;/|src=&quot;/' priv/feed.xml   # nothing
rg -o 'contact[^&"]*' priv/feed.xml              # contact/, not contact
```

After step 5 (footnotes), `/uses/` gains the footnote marker and an endnotes
section saying what KVM stands for. Nothing else changes, because it is the
only footnote and pages are not in the feed.

The `lustre:fragment` comments stay. They come from `common()` in
`src/site.gleam`, not from the djot rendering.

---

## Chapter 7: Code blocks that agree with each other

### The problem

Build the Home Assistant post and count the code block shapes:

```
 5  <pre data-file="lib/manager.ex"><code data-lang="elixir">   span.line per line
 4  <pre><code data-lang="elixir">                             span.line per line
 1  <pre><code data-lang="json">                               span.line per line
 1  <pre><code data-lang="iex">                                raw text, no spans
 3  <pre><code data-lang="text">                               raw text, no spans
```

glimra has no `iex` grammar, so the `result.unwrap` in the browser's
`highlighted`, from chapter 6, quietly substitutes a different DOM shape. The two
shapes are not cosmetically different, they are structurally different, and the
CSS treats them differently as a result.

`assets/app.css:181` sets `.line { display: block }` with a synthesized
`::after { content: "\A" }`, because glimra strips newline characters entirely
and expects CSS to put the line breaks back. Blocks without `.line` spans fall
back to `<pre>`'s own whitespace handling. They also keep their untrimmed
leading and trailing whitespace, because glimra trims its input and the fallback
path does not.

And `assets/app.css:158` paints a language badge from `data-lang`, suppressed for
`text` but not for `iex`. So the one block that is definitely not highlighted
advertises a language.

### The idea

One canonical shape, produced by every path. The fallback is not a different
rendering, it is the same rendering with the colours left out.

You chose warn-and-fall-back for unsupported languages, and glimra makes that
easy: `SyntaxHighlightingError` has an explicit `UnsupportedLanguage(language)`
variant, so you can distinguish "I do not know this language" from "something
went wrong".

### The work

Replace `result.unwrap` with a match on the error. `UnsupportedLanguage` prints a
warning naming the file and the language, then falls back. The other two variants
warn more loudly, because they mean something actually broke.

The fallback splits the source into lines and wraps each in
`<span class="line">`, and applies the same `string.trim` glimra applies. Both
paths now emit `<pre {attrs}><code data-lang="x"><span class="line">…`.

Decide what to do about the badge. Keeping it is defensible, since knowing a
block is `iex` is useful whether or not it is coloured. The current state, where
`text` is suppressed and `iex` is not, is the part that reads as an accident.

While you are here: `highlighted` passes
`set_theme(theme.default_theme())`, and those colours never render. `glimra.to_css`
is never called, `assets/app.css:210-437` hand-writes the entire token class list
against the Catppuccin variables, and `syntax_highlight` is generic over
`Config(has_theme)` so the call compiles without a theme at all. The hand-written
CSS is also the only correct choice, because `default_theme()` is Mocha with
hardcoded RGB and this site swaps palettes on `prefers-color-scheme`. Drop the
call and leave a comment saying why.

### Check it

```sh
rg -o '<pre[^>]*><code[^>]*>' priv/posts/*/index.html | sort | uniq -c
```

One structural shape. Then view the Home Assistant post and confirm the `iex`
block and the `elixir` blocks have the same padding, line height and corners.

---

## Chapter 8: The pipeline appears

### The problem

`src/build.gleam:main` is 80 lines that find content, render it, write it, and
then separately generate images. It builds `[index] ++ pages ++ posts` three
times, with `list.append` putting the single-element list on the left each time.

The feed is worse than untidy. `src/build.gleam:99` filters posts into feed items
in whatever order `simplifile.read_directory` returned them. The entries happen
to be newest first today. Nothing guarantees that.

### The idea

Every producer has the same shape: it looks at the site and returns files.

```gleam
pub type Generator = fn(Site, Targets) -> List(Output)
```

Once that is true, `main` is a pipeline and nothing else:

```gleam
pub fn main() {
  let site = content.discover(config)
  let targets = site.targets(site, assets)
  use <- validate.or_halt(links.validate(site, targets))

  [pages.generate, assets.generate, sitemap.generate, feed.generate, images.generate]
  |> list.flat_map(fn(generate) { generate(site, targets) })
  |> list.each(output.write(out_dir, _))
}
```

Adding a tag index is adding a function to that list. That is the extensibility
you were after, and notice it did not require a plugin system or a registry of
hooks. It required one type.

`targets` is computable before any rendering happens, which is the detail that
makes chapter 12 work. Chapter 2 did most of this for you: `route.Target`
enumerates everything the build emits a URL for, so `targets` is

```gleam
[route.Feed, route.Sitemap]
|> list.append({
  use page <- list.flat_map(site.pages)
  [route.Document(page.route), route.OgImage(page.route)]
})
|> list.map(route.target)
|> list.append(list.map(assets, route.asset))
```

and the only thing it needs beyond the type is the walk over `assets/`. Note that
OG images are in the set rather than beside it, which is what lets chapter 12
check a link to one. So you can validate every link before you render a single
element.

### The work

One module per generator under `src/generate/`. `images.gleam` is the interesting
one: OG images become ordinary `Output`s carrying `Bytes`, which means the
`simplifile.write_bits` whose `Result` was being discarded at
`src/build.gleam:142` now goes through the same `output.write` as everything
else.

Sort explicitly in `feed.generate` and `sitemap.generate`. Newest first for the
feed.

### Check it

```sh
just build && cp -r priv /tmp/a
just build && diff -r /tmp/a priv
```

Only the feed timestamp should differ. If anything else does, the build still
depends on directory iteration order somewhere.

---

## Chapter 9: The document model

### The problem

Every post is resolved twice per build. `render` at `src/site.gleam:160` and
`render_minimal` at `:167` each call `render.render`, and `render.render` at
`src/djot/render.gleam:102` runs `document` before it dispatches. So references
and footnotes are worked out once for the page and again for the feed. That is
cheap today. It is also exactly what the executable code block idea at the end of
this book trips over.

The resolved tree has no name. `render.document` returns `List(Container)`, a bare
list, and the only thing anything does with it is hand it to a `Renderer`. There
is nowhere to ask "which headings does this post have" or "which languages do its
code fences use", and chapter 12's link checker needs both answers.

And the feed's one real difference from the page, absolute URLs, is written as a
renderer, `feed` at `src/site.gleam:195`, even though it changes no markup. It
rewrites a URL and then hands the node to the standard rendering. That is a change
to the content dressed up as a change to the output.

### The idea

unified, the engine behind remark and rehype, splits document processing into
three phases: parse into a tree, run plugins over the tree, stringify. Hugo arrived
at the same split from the other side. Render hooks answer "this element should
look different", and `.Fragments` and `.TableOfContents` answer "tell me about
this page". Your version is three kinds of pass over one tree:

| Kind | Shape | Use it when |
| --- | --- | --- |
| Extract | `fn(Document) -> a` | you want a fact: headings, links, code languages, plain text |
| Transform | `fn(Document) -> Document` | same node types, different data: absolute URLs, resolved refs |
| Render override | a `Renderer` case | same data, different markup: `<figure>`, highlighted code |

The tree is parsed once, when the file is read, and stored on the page. Extracts
and transforms are pure, so they can run as often as anyone likes. Renderers stay
what chapter 6 made them.

What makes passes cheap to write is traversal written once. Chapter 12 would
otherwise have to know that footnote bodies are not reachable from the main
content, and that an image can sit inside a link's content. Those are traversal
facts. Solve them in one place and every pass matches only the nodes it cares
about.

One rule keeps the module honest: nothing under `src/djot/` imports `site`,
`route`, `path` or `config`. URLs are `String`s in the tree. Deciding whether a
link is internal is the checker's job, and keeping the site out of the tree is
what would let you lift `djot/` into its own package one day.

### The work

Split `src/djot/render.gleam`:

```
djot/document.gleam   Document, Block, Inline, map and fold
djot/parse.gleam      text -> Document (today's render.document and its helpers)
djot/extract.gleam    headings, links, code_languages, text
djot/transform.gleam  absolutize
djot/html.gleam       Renderer, render, the standard rendering
```

Rename `Container` to `Block` on the way, so the two node families read as a pair.
`Endnotes` stays a block, which is what makes footnote bodies part of the normal
traversal rather than a special case.

```gleam
// src/djot/document.gleam

pub type Document {
  Document(blocks: List(Block))
}

/// Bottom-up: `f` sees each node after its children were mapped.
pub fn map_inlines(doc: Document, f: fn(Inline) -> Inline) -> Document
pub fn map_blocks(doc: Document, f: fn(Block) -> Block) -> Document

/// Pre-order over every node, including footnote bodies and inlines nested
/// inside link content.
pub fn fold_inlines(doc: Document, from acc: a, with f: fn(a, Inline) -> a) -> a
pub fn fold_blocks(doc: Document, from acc: a, with f: fn(a, Block) -> a) -> a
```

A record with one field looks like ceremony. It is there for the name. `Document`
is what a page holds, what passes take and what renderers render, and a bare
`List(Block)` says none of that.

`parse.parse(text) -> Document` is the only caller of `jot.parse` and the only
module that imports `jot`. `site.parse` calls it, so `Body`'s `Djot` variant holds
a `document.Document`, parsed once. `html.render(doc, renderer)` stops resolving
anything. It walks the blocks it is handed.

Then the feed's renderer becomes a transform:

```gleam
// src/djot/transform.gleam

pub fn absolutize(doc: Document, against page: uri.Uri) -> Document {
  use node <- document.map_inlines(doc)
  case node {
    Link(..) -> Link(..node, url: absolute(node.url, page))
    Image(..) -> Image(..node, url: absolute(node.url, page))
    _ -> node
  }
}
```

`absolute` moves with it, trailing slash workaround and all. `render_minimal`
becomes `doc |> transform.absolutize(against: page_uri) |> html.render(djot_html.renderer())`,
and `site.feed` is deleted.

Write the extracts now, even though only chapter 12 calls most of them. Each is a
few lines over a fold, and they are how you find out whether the folds are right:

- `headings(doc) -> List(Heading)`, with `Heading(id:, level:, text:)`. The `id` is
  the attribute jot assigns to every heading (`build/packages/jot/src/jot.gleam:1173`).
- `links(doc) -> List(String)`, every `Link` and `Image` URL.
- `code_languages(doc) -> Set(String)`.
- `text(inlines) -> String`, today's `djot_html.text_content`, moved here because
  it is a fact about the tree, not markup. `figure` keeps using it for alt text.

### Check it

```sh
just build && diff -r /tmp/golden priv
```

Clean apart from the feed timestamp. Nothing renders differently: the same tree is
resolved once instead of twice, and the feed's URL rewrite happens before
rendering instead of during it.

```sh
rg -n '^import jot' src/                          # only djot/parse.gleam
rg -n '^import (site|route|path|config)' src/djot # nothing
```

---

## Chapter 10: Pages have kinds

### The problem

Ask the code what kinds of page the site has and you get two answers that have to
agree. `route.Route` at `src/route.gleam:11` says Home, Standalone and Article.
`site.Page` at `src/site.gleam:28` is one record for all three, so the kind lives
in `page.route`, and everything that cares has to ask the route.
`src/generate/feed.gleam:44` and `src/home.gleam:18` both match on
`page.route` to recover the information the flat list threw away.

The flat record also makes every page carry what only some pages have.
`published` is required, so Home gets `calendar.Date(2026, calendar.January, 18)`
typed into `src/build.gleam:111`. The five pages in `pages/` carry
`published = 2026-01-18` in their frontmatter, a date that means nothing on
`/uses/`. `source` is an `Option` because Home has no file, so every authored page,
which certainly has one, is still read through `option.Some`. And
`Computed(fn(Site) -> ...)` puts a function over the site inside a page inside the
site. You cannot compare two pages, `echo` one, or match on what a computed page
is.

The address types repeat the same problem on a smaller scale. There are five
names: `Route`, `Target`, `Rel`, `Abs`, and the private `Kind`. `Kind` says kind
but means "directory or file", which has nothing to do with what kind of page
something is. `Target` exists so chapter 8 could list everything the build writes
before writing it, in `paths` at `src/build.gleam:39`. That is a second list that
has to agree with the generators. Add a generator, forget `paths`, and chapter 12
would reject links to files that exist.

Finally, `site.gleam` does three jobs: it is the model, it parses files (`parse`
and `extract_meta`, `:51-79`), and it renders (`common` through `highlight`,
`:107-273`, over half the file).

### The idea

A page has a kind, and its kind decides what it holds and where it lives. Hugo
models exactly this with `.Kind`: home, page, section, taxonomy, term. In Gleam
the kind is the variant:

```gleam
pub type Page {
  Home
  Article(content: Content, published: calendar.Date)
  Standalone(content: Content)
}

/// Everything that came from one source file.
pub type Content {
  Content(slug: String, meta: Meta, source: Source, document: Document)
}
```

Read what the types now say. Only articles have a publication date, which is how
Jekyll, Zola and Astro all do it: dated posts, undated pages. Authored content
always has a `Source`, so the `Option` is gone. Home holds nothing, because
nothing about it is authored. Its title and description come from config, and
its body is a view over the other pages, so the `Computed` closure becomes an
ordinary `case` arm. `Content` is the word Hugo, Zola and Astro use for authored
material. It holds a little more than the word suggests, the slug and the file,
but it holds exactly what came from one source file and nothing that did not.

Fields that belong to one kind go on that kind's variant, not on `Content`. That
is the same move as Astro's per-collection schemas. `published` already lives on
`Article`. When articles get tags, `tags` goes there too.

The URL is a function of the page:

```gleam
pub fn path(page: Page) -> Path {
  case page {
    Home -> path.directory([])
    Article(content:, ..) -> path.directory(["posts", content.slug])
    Standalone(content:) -> path.directory([content.slug])
  }
}
```

That leaves one address type, `Path`, the address of anything the build writes.
Directory versus file is hidden inside it as its two private variants. Absolute
URLs are plain `uri.Uri` values from `path.url`. `Route` goes because `Page` is the
kind now. `Target` goes because chapter 12 takes the list of what exists from the
outputs themselves. `Abs` goes because it had one producer and every consumer
unwrapped it straight away.

`Route` did one job that still needs doing: linking to a page you are not holding.
The layout's nav and footer look pages up by slug, and the build fails if one is
missing. That is stricter than before, since `Standalone("abuot")` type-checked
fine. Links written in djot are chapter 12's job.

The generators stay exactly as they are. They are the extension point.

### The work

`src/path.gleam` replaces `src/route.gleam`:

```gleam
pub opaque type Path {
  Directory(segments: List(String))
  File(segments: List(String))
}

pub fn directory(segments: List(String)) -> Path
pub fn file(segments: List(String)) -> Path
pub fn feed() -> Path                   // /feed.xml
pub fn sitemap() -> Path                // /sitemap.xml
pub fn card(for page: Path) -> Path     // /images/og/posts/foo.png, /images/og/index.png
pub fn href(path: Path) -> String       // "/posts/foo/", "/feed.xml"
pub fn url(path: Path, on base: uri.Uri) -> uri.Uri
pub fn on_disk(path: Path) -> String    // "posts/foo/index.html"
```

Segments, not strings, so the four `let assert`s in `rel_page` and `rel_file` have
nothing left to check. `url` keeps the trailing slash, the way `abs_uri` does
today, so canonical tags and `transform.absolutize` use it directly. Assets keep
their relative path, split into segments, as a `path.file`.

`src/site.gleam` becomes the model and nothing else. `content.gleam` folds into it:

```gleam
pub type Site {
  Site(config: Config, pages: List(Page), assets: List(Asset))
}

pub type Meta { Meta(title: String, description: String) }
pub type Source { Source(path: String, revision: Option(Revision)) }
pub type Revision { Revision(hash: String, changed_at: calendar.Date) }
pub type Asset { Asset(from: String, path: Path) }

pub fn path(page: Page) -> Path
pub fn meta(config: Config, page: Page) -> Meta          // Home's comes from config
pub fn updated(site: Site, page: Page) -> Option(calendar.Date)
pub fn standalone(site: Site, slug: String) -> Result(Page, Nil)
```

`updated` reads the git revision for authored pages. For Home it is the newest
article's date, because the home page changes when a post is added, not when
`home.gleam` does.

There is deliberately no `articles(site)` query. Gleam cannot return "only the
`Article` variant" as a type without a second record, and the two consumers each
build their own projection anyway. So the feed and home each filter and sort:

```gleam
use page <- list.filter_map(site.pages)
case page {
  site.Article(content:, published:) -> Ok(#(published, entry(site, page, content)))
  _ -> Error(Nil)
}
```

Rendering moves out of `site.gleam` into `src/view/`:

```
view/page.gleam        render(site, page): picks the body, wraps it in the layout
view/layout.gleam      today's layout.gleam
view/home.gleam        today's home.gleam
view/content.gleam     header and body of an authored page (today's common and render)
view/prose.gleam       the browser Renderer: highlight, figure
view/components.gleam  today's component.gleam and the date functions from helper.gleam
```

```gleam
// src/view/page.gleam

pub fn render(site: Site, page: Page) -> Element(Nil) {
  let body = case page {
    site.Home -> home.view(site)
    site.Article(content:, published:) -> content.article(site.config, content, published)
    site.Standalone(content:) -> content.standalone(site.config, content)
  }
  layout.root(site, page, body)
}
```

The header follows the kinds. An article shows "Published on" plus the update and
commit, a standalone page shows "Updated on" and the commit, and Home shows its
title. `og:type` is a `case page` in the layout.

Nav and footer links become lookups:

```gleam
fn nav_link(site: Site, slug: String, label: String) -> Element(Nil) {
  let assert Ok(page) = site.standalone(site, slug)
    as "the layout links to a page that does not exist"
  html.a([attribute.href(page |> site.path |> path.href)], [html.text(label)])
}
```

The feed renders `transform.absolutize(content.document, against: page |> site.path |> path.url(on: base))`.

Reading stays in `build.gleam` for one more chapter, but it now builds kinds:
`posts/` becomes `Article`, which requires `published`, and `pages/` becomes
`Standalone`, which does not read it. Delete the `published` line from the five
files in `pages/`. Home is `site.Home`, and the hand-typed date goes with it.

`og_image.generate` passes `date` only for articles, and an empty string
otherwise. `src/template.typ:18` prints it as text, so the line just stays blank.

`paths` in `build.gleam` survives one more chapter as a `List(Path)`.

### Check it

```sh
just build && diff -r /tmp/golden priv
```

Expect exactly these differences and no others:

- `/` loses its "Published on January 18, 2026" line and its commit link.
- The five standalone pages say "Updated on" with their git date instead of
  "Published on".
- In `sitemap.xml`, Home's `lastmod` becomes the newest article's date.
- The cards for Home and the standalone pages lose their date line.

```sh
rg -n 'route\.' src/                # nothing
rg -n 'calendar\.Date\(' src/       # nothing, the fake date is gone
rg -n '^published' pages/           # nothing
```

---

## Chapter 11: Discovery is a boundary

### The problem

Reading content is spread over two modules and fails by crashing. `build.gleam`
lists directories, in `read_pages` at `:55` and `files` at `:49`. `site.parse`
decodes frontmatter with four `let assert`s (`src/site.gleam:73-76`) and panics on
an unknown extension (`:62`). A typo in one post's frontmatter crashes the build
with a `let assert` pointing at `site.gleam`. It does not name the file, and if
two files are broken you find out about one of them.

Drafts are a folder, `./drafts` at `src/build.gleam:33`. Hugo, Zola and Eleventy
all mark drafts with `draft = true` in frontmatter and include them with a build
flag. Jekyll's `_drafts` folder is the exception. With a flag, publishing is a
one-line change: the file does not move, its git history stays in one place, and
its URL does not change at the moment you publish.

And the generators take `paths` that none of them read, which is why every one of
them names the argument `_paths`. `og_image.generate` is curried so it can
receive its template, which makes it the one generator with a different shape.

### The idea

Chapter 4 applied "parse, don't validate" to git. This chapter applies it to every
input. One module does all the reading and returns either a complete `Site` or
every problem at once, each one naming its file:

```gleam
pub type Problem {
  Problem(file: String, issue: Issue)
}

pub type Issue {
  Unreadable(simplifile.FileError)
  UnsupportedFormat(extension: String)
  BadFrontmatter(reason: String)
  MissingField(name: String)
  InvalidSlug(slug: String)
  DuplicatePath(path: String, other: String)
}
```

Chapter 12 adds its link problems to the same type, so a single reporter prints
everything the build has to say.

Slugs are restricted to `[a-z0-9-]`. They become URLs and directory names, and
checking them once means nothing downstream ever has to think about escaping.

### The work

```gleam
// src/discover.gleam

pub fn site(config: Config) -> Result(Site, List(Problem))
```

It reads `posts/` as articles, `pages/` as standalone pages, walks `assets/`,
reads the card template, and resolves one git revision per file. Frontmatter is
decoded per kind. Posts need `title`, `description` and `published`, with an
optional `draft`. Pages need `title` and `description`. It reads every file before
deciding anything, collects every problem, and returns `Error` if there are any.

Two pages that land on the same `site.path` are a `DuplicatePath`. Today that
would silently overwrite one output with the other. The easy way to hit it is
`pages/uses.dj` next to `pages/uses.djot`.

Drafts become `draft = true` in a post's frontmatter. `Config` gains
`drafts: Bool`, set where `show_drafts` is computed today (`src/build.gleam:79`),
and `discover` drops drafts when it is `False`. Whether drafts are shown is a
decision about reading, not a fact about a page, so `Page` does not change. If you
want a "draft" banner in development one day, that is a field on `Article`.
Delete `drafts_path`.

`Site` gains `card_template: String`, so `og_image.generate` loses its curried
argument. Then `generate.Generator` becomes `fn(Site) -> List(Output)`, and
`paths` in `build.gleam` is deleted. Chapter 12 gets that set from the outputs.

`build.gleam` ends up as a pipeline with I/O at both ends:

```gleam
pub fn main() {
  let config = read_config()   // SITE_URL and BLOG_ENV, as in chapter 3
  case discover.site(config) {
    Error(problems) -> problem.exit(problems)
    Ok(site) ->
      [pages.generate, assets.generate, sitemap.generate, feed.generate, og_image.generate]
      |> list.flat_map(fn(generate) { generate(site) })
      |> list.each(output.write(out_dir, _))
  }
}
```

`problem.exit` prints one line per problem, `posts/foo.dj: missing field "published"`,
and exits non-zero through a one-line FFI to `erlang:halt/1`.

### Check it

```sh
just build && diff -r /tmp/golden priv
```

Clean apart from the feed timestamp. Then break things on purpose:

- Delete `title` from one post and `description` from another. Both are reported,
  each with its file.
- Copy `pages/uses.dj` to `pages/uses.djot`, and get a `DuplicatePath`.
- Rename a post to `Foo Bar.dj`, and get an `InvalidSlug`.
- Add `draft = true` to a post. `just build` leaves it out of the page, home, feed,
  sitemap and cards. `just dev` puts it back.

---

## Chapter 12: Links that cannot rot

### The problem

All 92 inline links and 5 images in `posts/` and `pages/` are bare strings.
Rename a slug and every link to it breaks silently.

You fixed the two non-canonical ones back in chapter 2. Nothing stops the next
one being written tomorrow.

### The idea

Be straight about what is achievable. Gleam's compiler never sees your `.dj`
files, so there is no way to make `gleam build` fail on a bad link. The check has
to happen at build time. For a static site generator that is the same guarantee
in practice: a broken internal link cannot reach the deploy.

Two layers, which is what you picked.

Typed references make the common case unforgeable. The generator injects a
reference table built from the routes, so you write `[the uses page][page:uses]`
and never type a URL at all. Rename a slug and every link follows.

The validator catches everything else. Raw URLs stay legal as an escape hatch,
and get checked against the same set of targets.

There is a rule worth stating plainly, because it decides what the validator does
with a link like `/uses` that the server would happily serve anyway:

> Redirects are for URLs you no longer control. Canonicalization is for URLs you
> emit.

The `.html` rules in `caddy/blog.part:13-27` are a good safety net for links
other people have bookmarked, and they should stay. They are not a licence for
your own pages to link to the non-canonical form. So the validator canonicalizes
every internal destination through `route` and rejects anything that does not
already match, with the corrected spelling in the error. The server coping is not
the same as the link being right.

One more decision, and it replaces the `Target` set chapter 8 planned. The set of
things a link may point at is the set of paths the build actually produces. So
the build renders everything into memory, checks the links against the outputs'
paths, and writes only if the check passes. Nothing reaches disk before then, so
checking after rendering gives up no safety, and there is no second list that can
drift from the generators. The cost is that the cards get rendered before a bad
link stops the build. That is a few seconds. If it ever matters, make the card's
contents lazy.

### The work

Two pieces: typed references in `discover`, and a check in `src/check.gleam`.

**Typed references.** Write `[the uses page][page:uses]` or
`[that post][post:composable-sftp-streams]`. The two prefixes mirror the two
authored kinds. jot does not know these keys, and `resolve_url` in `djot/parse`
falls back to the key itself, so the link reaches the tree with `page:uses` as
its URL. A transform fills it in:

```gleam
pub fn resolve(doc: Document, table: Dict(String, String)) -> Document
```

The table is a plain `Dict(String, String)` from key to href, so `djot/` still
knows nothing about the site. `discover` builds it from `site.path` of every page,
which means reading becomes two passes: parse every file, then resolve every
document against the table built from all of them. A key the table does not have
stays as it is, and the check reports it. A fragment rides along:
`page:uses#Camera` looks up `page:uses` and appends `#Camera`, and the check then
verifies the fragment like any other.

One thing jot does that you need to know: `references` is not empty even though
no document defines a single `[id]: url` line. `jot.parse` seeds it with an
anchor per heading, which is why the lone `[Homex][]` resolves today. A heading
would have to be literally titled `page:uses` to collide, but if one ever is, the
heading wins inside jot. The check catches it, because the URL is then a fragment
and not the page.

**The check.**

```gleam
pub fn links(site: Site, outputs: List(Output)) -> List(Problem)
```

For every authored page, take `extract.links(content.document)`. Chapter 9's fold
already walks footnote bodies and the image nested inside a link at
`posts/composable-sftp-streams.dj:205`, so nothing here has to know about them.
Then classify each link:

- A leftover `page:` or `post:` key is an `UnknownPage`. Check this first,
  because `uri.parse` reads `page:` as a scheme.
- Anything else with a scheme (`https:`, `mailto:`) is left alone and never fetched.
- A bare `#frag` checks against `extract.headings` of the same document.
- Anything else is resolved against the page's own URL, the same `uri.merge` as
  `absolutize`, and must equal the `path.href` of some output. If the path is
  right but the fragment is not among that page's heading ids, it is a
  `MissingFragment`.
- A path that misses, but would hit with a trailing slash added or with `.html`
  or `/index.html` removed, is a `NotCanonical` with the right spelling in the
  error. That is the redirect rule above, done by the build.

The issues join chapter 11's type: `BrokenLink(url)`, `NotCanonical(url, use:)`,
`MissingFragment(url)`, `UnknownPage(key)`. `Problem.file` is the page's source
path, so errors come out by file and destination. jot has no positions, so line
numbers are not available.

`main` gains one step between generating and writing:

```gleam
let outputs = list.flat_map(generators, fn(generate) { generate(site) })
case check.links(site, outputs) {
  [] -> list.each(outputs, output.write(out_dir, _))
  problems -> problem.exit(problems)
}
```

Links the Gleam code writes are not checked here, and do not need to be. The nav
and footer look up their pages (chapter 10), and Home's links come from
`site.path` of pages that exist.

### Check it

The first run should pass, because chapter 2 already fixed the two links that
would have failed it.

So prove it works by breaking things on purpose, one at a time, and confirming
each is caught: a mistyped image path, an unknown reference key, a renamed slug
with a stale link pointing at it, a fragment that does not exist, and
`[x][page:nope]`.

Then convert one real link to a typed one, say `/uses/#Camera` in `pages/now.dj`
to `[...][page:uses#Camera]`, and check that the output is byte-identical.

Then put back exactly the two you fixed in chapter 2, `/contact.html` and
`/uses#Camera`, and check that both are rejected with the canonical spelling in
the error. That is the rule above doing its job: Caddy answers both with a clean
308, so nothing is broken, and the build refuses them anyway.

---

## Chapter 13: Clean up and lock it down

### The problem

There are no tests. `test/kevinschweikert_test.gleam` is the gleeunit stub and
nothing else.

### The idea

Everything after `discover` is now a pure function over plain data, which makes
it easy to test. A test can build a `Site` by hand, with no disk and no git
repository, and call anything. `path.gleam` is still the module most worth
testing, because everything else depends on it being right. The djot passes come
second, because chapter 12 trusts the folds to reach every node.

### The work

Delete what is left of the old structure: `route.gleam`, `content.gleam`,
`TODO2.md` (chapter 10 did what it describes), and any module that only
re-exports something that moved.

Write `test/path_test.gleam`. `href` is the one to be thorough with, since it is
the only thing that decides the URL shape: a `directory` comes back with a
trailing slash, and a `file`, `feed` or `sitemap` must not. Cover `on_disk` for
nested pages like `posts/some-post`, `card` for Home (`/images/og/index.png`) and
for an article, and `url` keeping the trailing slash.

Write `test/djot_test.gleam`. `fold_inlines` reaches a link inside a footnote and
an image inside a link. `absolutize` turns `/contact/` into an absolute URL that
still ends in a slash. `resolve` fills in `page:` keys and keeps the fragment.

Write `test/check_test.gleam` against a two-page `Site` built in the test: a good
link passes, and a broken link, a non-canonical link and a missing fragment each
come back as the right `Issue`.

Then check the dead API surface that accumulated: `git.short_hash`,
`typst.set_options`, and five unused helpers in `opengraph.gleam`
(`site_name`, `image_type`, `image_width`, `image_height`, `image_alt`). Delete
or use them.

### Check it

```sh
gleam test
gleam build          # warning-clean
just build && diff -r /tmp/golden priv
```

Walk the final diff one last time. Every difference should be a fix you can name.

---

## Where everything went

| Was | Is |
| --- | --- |
| `build.gleam` | stays, the pipeline: config, discover, generate, check, write |
| `page.gleam` | split: `site.gleam` (the model), `discover.gleam` (reading), `view/content.gleam` (rendering) |
| `content.gleam` | folded into `site.gleam` |
| `site.gleam`'s rendering half | `view/content.gleam` and `view/prose.gleam` |
| `index.gleam`, `home.gleam` | `view/home.gleam`, an arm of `view/page.render` |
| `layout.gleam` | `view/layout.gleam`, nav links looked up by slug |
| `djot.gleam`, `djot/render.gleam` | `djot/document`, `parse`, `extract`, `transform`, `html` |
| `render.gleam` | deleted, it was dead |
| `helper.gleam`, `component.gleam` | `view/components.gleam`, XML bits move to the generators |
| `sitemap.gleam`, `feed.gleam` | `generate/`, as `fn(Site) -> List(Output)` |
| `atom.gleam`, `opengraph.gleam`, `typst.gleam` | `vendor/`, unchanged |
| `route.gleam` | `path.gleam`: one opaque `Path`, the URL computed by `site.path(page)` |
| `drafts/` | `draft = true` in frontmatter |

The types, all of them:

| Type | What it is |
| --- | --- |
| `Site` | Everything the build reads: config, pages, assets, card template. No markup, no I/O. |
| `Page` | Anything served as HTML. The variant is the kind: `Home`, `Article`, `Standalone`. |
| `Content` | Everything that came from one source file: slug, meta, source, document. |
| `Meta` | Title and description. |
| `Source`, `Revision` | The file and what git knows about it, resolved once. |
| `Path` | Where any output lives. Directory or file is hidden inside. |
| `Output` | A path and its contents. |
| `Document` | The parsed djot tree. |
| `Problem` | Anything the build refuses, with the file it came from. |

## Page kinds you can add later

Each one is a `Page` variant and a line in `site.path`. The compiler then points
at the view dispatch, `site.meta` and anything else that matches on pages.
Generated kinds also need a line in `discover` that creates them. Authored kinds
carry a `Content`, generated ones do not, which is the whole reason `Content`
exists.

| Kind | Authored or generated | Notes |
| --- | --- | --- |
| `TagIndex` (all tags) / `Tag(name)` (one tag's posts) | generated | Hugo's `taxonomy` and `term` kinds. `tags` goes on `Article`. |
| `Archive(year)` or a `/posts/` listing | generated | Hugo's `section` kind |
| `Note` / TIL | authored, dated | A second dated collection, short, maybe outside the main feed |
| `Project` / `Talk` | authored | Kind-specific fields (repo URL, event, slides) go on the variant |
| `Series(name)` | generated | Groups multi-part articles |
| `NotFound` | generated | Served as `/404.html`, a file rather than a directory, which `site.path` handles |
| Redirect / alias | generated | Not a page, an old address pointing at one. See the third idea below. |

## One thing deliberately left out

Replacing glimra. It is a Rust NIF you maintain a fork of, it compiles from
source on every clean build, and its grammar list has no `iex`, `toml`, `yaml`,
`diff` or `sql`.

[Lumis](https://lumis.sh) looks like the strongest candidate. It is leandrocp's
Tree-sitter highlighter, recently renamed from `autumn`, and it lines up with
this project on four points.

It runs server-side on the BEAM. Lumis requires `rustler_precompiled ~> 0.8`, so
it downloads prebuilt binaries rather than compiling Rust locally, which is the
same mechanism `typst` already uses here. Watch your own build log for
`Copying NIF from cache and extracting to .../libtypst_nif-…`. The WASM in the
`lumis_wasm_*` package names is only how the grammars are shipped; they execute
inside the NIF, with no JS runtime anywhere.

`lumis_wasm_iex` exists, at 0.26.1. That is the exact gap that makes your one
`iex` block render unhighlighted today. There are also packages for `toml`,
`yaml`, `diff`, `sql` and `gleam`.

The `html_linked` formatter emits class names and leaves the colours to your
stylesheet, which is precisely the arrangement `assets/app.css:210-437` already
has. There is also an `html_multi_theme` formatter for `prefers-color-scheme`
switching, which is the thing glimra structurally cannot do: `theme.default_theme()`
is Mocha with hardcoded RGB, so it can only ever serve half your palette.
Catppuccin is available as `catppuccin_latte`, `catppuccin_frappe` and
`catppuccin-mocha` if you ever want to generate that CSS instead of hand-writing
it.

The call shape, verified against the 0.10.2 package source rather than the
rendered docs:

```elixir
@spec highlight(String.t(), options()) ::
        {:ok, String.t()} | {:error, Lumis.RenderError.t()}

Lumis.highlight(code, formatter: {:html_linked, language: "elixir"})
```

The language goes **inside** the formatter tuple, not at the top level. The
formatter is either a bare atom (`:html_linked`) or a `{atom, keyword}` pair.
`highlight!/2` returns a bare `String.t()` and raises `Lumis.HighlightError`.

Three things turned out better than I assumed, and they change what to ask for in
a Gleam binding. The author has said he is open to a Gleam-native package reusing
the same NIFs, so the ask is to preserve these rather than add them.

**The error type already makes the distinction chapter 7 needs**, and makes it
better than glimra does. `Lumis.ParserError` is raised for a missing or
unloadable grammar and carries `:language`, `:package`, `:reason` and `:detail`.
`Lumis.RenderError` is documented as "highlighting failed for a reason that is
not a missing parser". So the warning chapter 7 prints can name the hex package
to add, not just the language that failed. One wrinkle for Gleam: `@type reason()
:: atom()` is deliberately open, and the docs say a `case` over it needs a
catch-all clause. A Gleam binding needs an `Other(String)` variant.

**`available_languages/0` exists**, returning maps with `id`, `name`, `aliases`
and `extensions`, alongside a companion that reports which grammars are loaded in
this VM. That makes the better idea viable: chapter 9 already walks every
document to validate links, so code fence languages can be checked in the same
pass. You would learn about a typo'd or ungrammared fence once, up front, with a
list, rather than per-render or not at all. Strictly better than the
warn-on-fallback that chapter 7 settles for.

**256 pre-generated theme stylesheets ship in the package**, at
`priv/static/css/`, including all four Catppuccin variants. So you would not
hand-write token CSS at all, which is what `assets/app.css:210-437` does today:

```css
/* catppuccin_mocha */
.lumis { color: #cdd6f4; background-color: #1e1e2e; }
.l-comment { color: #9399b2; font-style: italic; }
```

Note the cost buried in that. Lumis namespaces its classes `l-*` with a `.lumis`
root, and emits per-line markup as `<span class="l-line" data-line="2">`. glimra
emits `line`, `variable`, `string.special` and so on. So a swap means replacing
your `@layer highlight` block, not adapting it. Shipping `catppuccin_latte.css`
and `catppuccin_mocha.css` behind your existing `prefers-color-scheme` swap is
the obvious route, and it is less code than you have now, but the hex values
would live separately from the `@catppuccin/tailwindcss` variables the rest of
the site uses rather than sharing them.

Returning an HTML `String` rather than a Lustre `Element` stays right for a
general package, since it keeps lustre out of the dependency tree.
`element.unsafe_raw_html` embeds a string without parsing it, so the cost is nil
and chapter 6's `highlighted` absorbs it unchanged.

Three caveats survive. Lumis is at 0.10.2 and pre-1.0, published days ago and
recently renamed from `autumn`, so expect movement. Every language is its own hex
dependency, so `gleam.toml` grows an entry per grammar. And all grammars share
one Tree-sitter WASM store with a per-process memory cap that is never reclaimed,
so there is an upper bound on how many languages one VM can load. At four
languages that is irrelevant, but it is worth knowing it exists.

None of this belongs in the rewrite. It is a real decision with real tradeoffs,
and bundling it into a type-level restructure would make both harder to judge.
Chapter 6 puts the highlighter behind a single function, so when you do decide,
it is a small change rather than a large one. If the Gleam package lands in the
meantime, that function becomes a direct call instead of an FFI wrapper, and
nothing else in the book changes.

---

## Three ideas for after the book, not during it

The first two came up while chapter 6 was fresh. Both touch the same
resolve/render split, and neither should be designed until the rest of the
chapters are. Revisit once chapters 9 through 13 are done, since chapter 9's
transforms, the output set and chapter 12's check are exactly the things either
idea would plug into. The third came up while designing chapter 10's page kinds.

**Local image paths that work in a markdown previewer.** The want: write
`![](../images/foo.jpg)` in a djot source file, have a local markdown viewer
resolve it as a plain relative path, and have the build copy the file into its
output location and rewrite the URL to the site path. The image case is the
easier of the two, because a URL is still a URL: an `Image`'s `url` can be
rewritten in place by a chapter 9 transform that runs in `discover`, so
`djot/html` never has to know images can come from disk.

The one trap worth remembering by the time this gets built: the pre-pass
produces two facts about the same file, the rewritten URL and the `Output`
that copies it, and those must come from one function, not two. Build both
from the same underlying `path.Path` value in a single call
(`resolve_local_image(src_path, dest) -> #(String, output.Output)`) rather
than computing a URL string in one place and an `Output.path` in another.
That is the same bug chapter 6 hit with the footnote ref/entry ids agreeing by
luck instead of by construction, wearing a different hat.

**Executable code blocks**, marked somehow in the djot source, run at build
time, with their result spliced in below the block. This one is not a small
extension of the image idea, because of a constraint chapter 4 already argued
for at length: rendering must stay a pure function from a value to markup.
Running code is I/O, so it belongs in `discover` and nowhere later. Running a
block twice is slow, and if the code is not perfectly deterministic the browser
and the feed could show different output for the same block. That is the
`git_hash`-inside-`common()` bug from chapter 4, recurring for something far
more expensive than a shell call.

Chapter 9 already removed the main obstacle: the document is parsed once and
stored on the page, and both outputs render that same value. What remains is
that a captured result is a fact `Codeblock` has no field for. It becomes a new
field on `djot/document`'s own `Codeblock`, filled in by a step in `discover`
that runs each marked block once, after parsing and before anything renders.

Neither idea is designed yet. Before building either: decide how the image
pass's copy outputs reach the generators (probably a field on `Content`), and
decide how execution results get cached so an unrelated build does not re-run
every executable block, and what renders when one fails.

**Owning the server config.** Today `Caddyfile`, `caddy/blog.part` and
`caddy/blog.Caddyfile` are written by hand, and the two `.html` regex redirects
in `blog.part` encode the site's URL scheme a second time, in a second
language. The build already knows every path and every old address, so it can
write the server config itself. Four pieces, which belong together:

- **A `NotFound` page.** A `Page` variant whose `site.path` is
  `path.file(["404.html"])`. It renders through the normal layout, with no card,
  no canonical link, no sitemap entry and `noindex`. Each of those is a `case`
  over pages, so the compiler asks.
- **Redirects as data.** `Redirect(from: Path, to: Path)`, from
  `site.redirects(site)`: each page's legacy `.html` address, plus any
  `aliases = [...]` in frontmatter for renamed slugs, which is how Zola and Hugo
  do it. Redirects are not outputs, since they write no file. Three things read
  the list: the Caddy emitter, chapter 12's check (a link to a redirect source
  gets the target in its error) and the duplicate path check.
- **The environment as a type.** `Env = Development | Production`, and
  `config(env)` gives the base URL, whether drafts are shown, the server root
  (`./dist/public` or `/static/blog`) and extra imports (`badpaths` in
  production only). Caddy accepts a URL as a site address, so the canonical URLs
  and the server address cannot disagree. `SITE_URL` goes.
- **A generated Caddyfile.** `caddy.config(config, redirects) -> String`, written
  to `dist/caddy/blog.Caddyfile`, outside the served folder. It contains the
  site address, root, `encode`, the cache and `.livemd` headers as constants, one
  `redir ... 308` per redirect (real server-side redirects, which Google prefers
  over meta refresh), a `handle_errors 404` block and `file_server`. The
  `/x/index.html` redirects can be emitted per page the same way, with no regex.
  `priv/` becomes `dist/public/`, `just deploy` rsyncs both folders, and
  `just dev` runs `caddy run --config dist/caddy/blog.Caddyfile`. All three
  hand-written Caddy files are deleted.

Run `caddy validate --config dist/caddy/blog.Caddyfile` in `just build`, so a
broken config fails locally rather than on the server. Chapter 11 already
restricts slugs to `[a-z0-9-]`, so nothing in the generated file needs escaping.
This deliberately ties the generator to Caddy. If you ever move to Netlify or
Cloudflare, you write a `_redirects` emitter from the same list, and nothing
else changes.
