# Rebuilding the generator

A step by step rewrite of this site's static site generator, in eleven chapters.

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

**The `Renderer(view)` record is the wrong size.** It has 22 fields and is
generic over `view`. In this codebase `view` is always `element.Element(Nil)`,
there are exactly two instances of the record, and they differ in two fields, one
of which is identical in both anyway. Roughly 290 lines of `src/djot.gleam`, plus
all the `render_block` and `render_inline` dispatch, exist to vary one real
behaviour: whether code blocks get syntax highlighted.

That last one deserves a word of defence for the original. lustre_ssg is a
library. Its consumers are unknown, so a fully general renderer record is the
right call there. You are a known consumer with one target. Copying the
generality without the uncertainty that justified it is how abstractions go
stale.

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
else. That turns out to be exactly what link checking needs in chapter 9, which
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

`route.rel_page` takes a string and performs three `let assert`s on it:

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

### The work

```gleam
// src/route.gleam

pub type Route {
  Home
  Standalone(slug: String)
  Article(slug: String)
}

/// Total. A Route cannot name a path that is not a valid relative URL.
pub fn of(route: Route) -> Rel

/// Total. Asset paths come from walking assets/, so they are known good.
pub fn asset(path: String) -> Rel
```

`Site(slug)` becomes `Standalone(slug)`, because in chapter 5 `Site` starts
meaning the whole site.

Note what happens to `Kind`. Today `rel_page` and `rel_file` ask the caller to
pick `Page` or `File`. But a `Route` is always a page and an asset is always a
file, so these two constructors set `Kind` correctly by construction and the
caller cannot get it wrong.

Delete `fs_abs_path` and `abs_from_base`. Neither has a caller.

Then fix the layout. Nav entries come from `route.of(Standalone("about"))` and
friends, so the layout cannot name a page that does not exist, and the footer's
`/impress.html` becomes `/impress/` as a consequence rather than as a patch.

Change `html.meta` to `html.link` on line 20 while you are in the file. One word,
and it is the difference between having canonical tags and not.

Two links in content point at the non-canonical form. Fix them here, because
chapter 9 will reject them and you would rather meet them now than as a wall of
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

The diff shows the canonical tags changing element, `/impress.html` becoming
`/impress/`, and the two content links picking up their slashes. Nothing else.
The site now stops depending on Caddy redirects for its own links.

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

`src/config.gleam` is five functions returning constants. `root_url()` parses a
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

`route.abs` currently calls `config.root_url()` internally. It now takes the base
as an argument instead. That is slightly more typing at each call site and much
more honest: converting a relative route to an absolute one genuinely does depend
on where the site lives.

### Check it

Clean diff. Then try it properly: build with a `Config` whose base is
`http://localhost:8080` and confirm `sitemap.xml` and `feed.xml` come out with
local URLs. That capability is the whole point of the chapter.

---

## Chapter 4: Finish constructing the page

### The problem

Here is `common()`, from `src/page.gleam:208`, which runs for every page:

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

pub type Meta {
  Meta(title: String, description: String, author: String)
}
```

Discovery resolves the `Revision` and stores it. `common()` reads
`page.source.revision` and does no I/O.

While you are in the FFI, quote the path.

### Check it

```sh
# before and after, on the same content
time just build
```

The build currently takes about a second, most of it process spawning. Expect
that to drop. More importantly, rendering is now a pure function, which is what
makes chapter 11's tests possible.

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
means the link checker in chapter 9 reads exactly the same tree the renderer
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

Two types go away here. `page.Image` has three variants and only one is ever
constructed: `extract_meta` at `src/page.gleam:109` hardcodes `Generated`, so
`None` and `File(url:)` are dead. The OG image path is a function of the route,
so make it a function.

`page.SitemapItem` and `page.FeedItem` also go. They are projections, and
projections do not need types. `FeedItem` is the worse of the two: it carries a
pre-rendered `html: String` field, which means rendering happens during what
looks like a data conversion.

### Check it

`index.gleam` becomes `view/home.gleam` and returns a function rather than being
called eagerly. The hardcoded January 2026 date disappears, replaced by the git
revision of the view file itself. Expect that one date to change in the diff.

---

## Chapter 6: Twenty-two fields become two

### The problem

`src/djot.gleam` defines a 22-field renderer record, generic over `view`. The
project creates two of them. `page.styled_renderer` is written as
`Renderer(..default_renderer(), codeblock: ..., image: ...)`, so it overrides two
fields. The `image` override produces a `<figure>` with a caption. The dead
`src/render.gleam` contains a third copy of that same image override.

So: one record, 22 fields, two instances, one genuine difference.

### The idea

An abstraction should be the size of the variation it covers. The variation here
is two functions, so the abstraction is two functions.

```gleam
// src/djot/render.gleam

pub type Context {
  Context(
    link: fn(jot.Destination) -> String,
    code: fn(Option(String), String) -> element.Element(Nil),
  )
}

pub fn document(doc: jot.Document, ctx: Context) -> List(element.Element(Nil))
```

The site passes a `code` that calls glimra. The feed passes one that does not.
Everything else is a direct pattern match on `jot.Container` and `jot.Inline`.

There is a second payoff. glimra is now named in exactly one place, the function
you pass in. You mentioned wanting to look at alternatives, and this is what
makes that a one-function change instead of an archaeology project. Its grammar
list covers bash, c, css, elixir, erlang, gleam, go, html, javascript, json,
python and rust, which is why your `iex` block is not highlighted today.

Note that `link` returns `String`, not `Result`. That is deliberate and it is a
promise chapter 9 will keep: validation runs before rendering, so by the time the
renderer sees a destination it is already known good.

### The work

Write `src/djot/render.gleam` as a plain recursive function. Delete
`src/djot.gleam` and `src/render.gleam`.

Three bugs are worth fixing while you have the file open, because they are all
one-line consequences of the old structure.

`src/djot.gleam:181` prepends `attribute.class(class)` to attributes that jot has
already populated with that same class, so `::: info` renders as
`<div class="info info">`.

`src/djot.gleam:381` renders `jot.Footnote(_)` as `renderer.text("")`, and `:202`
discards the `footnotes` field of the document entirely. `pages/uses.dj:11` uses
a footnote and `:50` defines it, so the marker vanishes and "KVM stands for
Keyboard, Video and Mouse" never reaches the page. That is live content loss.
`Document.footnotes` holds fully parsed blocks, so rendering them reuses the
block path you just wrote.

`src/djot.gleam:77` passes the language through unlowercased while glimra
lowercases it, so a `JSON` fence would produce different `data-lang` values on
the page and in the feed.

### Check it

This is the chapter most likely to produce diff noise, and that is the point of
having a golden copy. Work through every difference until each one is either
intended or gone.

Expect: `class="info info"` becomes `class="info"`, the footnote appears, and the
`lustre:fragment` comments disappear if you build flat element lists instead of
calling `element.fragment`.

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

glimra has no `iex` grammar, so `result.unwrap` at `src/page.gleam:281` quietly
substitutes a different DOM shape. The two shapes are not cosmetically different,
they are structurally different, and the CSS treats them differently as a result.

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

While you are here: `src/page.gleam:279` passes
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
makes chapter 9 work. Page routes come from `Site.pages`, asset paths from
walking `assets/`, OG image paths from the routes. So you can validate every link
before you render a single element.

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

## Chapter 9: Links that cannot rot

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

### The work

A traversal and a check, in `src/djot/links.gleam`.

Four things about jot will bite you if you do not know them in advance.

There is no fold or visitor helper, and no position information on any node. You
hand-write the walk over all 9 `Container` and 16 `Inline` variants, and errors
are reported by file and destination rather than line and column.

`document.footnotes` is a separate `Dict(String, List(Container))` whose bodies
are fully parsed blocks. They are not reachable from `document.content`, so the
walk has to visit them separately or links inside footnotes go unchecked.

You have to descend into `Link.content`, because
`posts/composable-sftp-streams.dj:205` nests an image inside a link.

And `references` is not empty even though no document defines a single
`[id]: url` line. `jot.parse` seeds it with an auto-generated anchor per heading.
That is why the lone reference link `[Homex][]` already resolves today. So when
you inject route keys, a collision with a heading anchor must be an error rather
than a silent overwrite.

Classify destinations before checking them. Anything with a scheme is left alone
and never fetched. A bare `#frag` checks against the current document's heading
ids. A `/path#frag` canonicalizes the path, checks it against targets, then
checks the fragment against the target document's heading ids, which works
because everything is parsed by the time validation runs.

### Check it

The first run should pass, because chapter 2 already fixed the two links that
would have failed it.

So prove it works by breaking things on purpose, one at a time, and confirming
each is caught: a mistyped image path, an unknown reference key, a renamed slug
with a stale link pointing at it, a fragment that does not exist.

Then put back exactly the two you fixed in chapter 2, `/contact.html` and
`/uses#Camera`, and check that both are rejected with the canonical spelling in
the error. That is the rule above doing its job: Caddy answers both with a clean
308, so nothing is broken, and the build refuses them anyway.

---

## Chapter 10: Clean up and lock it down

### The problem

There are no tests. `test/kevinschweikert_test.gleam` is the gleeunit stub and
nothing else.

### The idea

`route.gleam` is the module most worth testing and the easiest to test, now that
it has total constructors and no I/O. It is also the module everything else
depends on being right.

### The work

Delete what is left of the old structure: `page.gleam`, `index.gleam`,
`build.gleam`, and `render.gleam` if chapter 6 did not already take it.

Write `test/route_test.gleam`. Cover `canonicalize` for both kinds, `of` and
`asset` round-tripping through `rel_string`, and `fs_rel_path` for nested slugs
like `posts/some-post`.

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
| `build.gleam` | `blog.gleam`, the pipeline |
| `page.gleam` | split: `content.gleam`, `site.gleam`, `view/article.gleam` |
| `index.gleam` | `view/home.gleam`, returning a `Computed` body |
| `djot.gleam` | `djot/render.gleam`, two fields instead of 22 |
| `render.gleam` | deleted, it was dead |
| `helper.gleam` | `view/components.gleam`, or a `date` module |
| `component.gleam` | `view/components.gleam`, XML bits move to the generators |
| `sitemap.gleam`, `feed.gleam` | `generate/`, as `fn(Site, Targets) -> List(Output)` |
| `atom.gleam`, `opengraph.gleam` | `vendor/`, unchanged |
| `route.gleam` | stays, plus `Route` and total constructors |

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
and chapter 6's `code: fn(Option(String), String) -> element.Element(Nil)`
absorbs it unchanged.

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
