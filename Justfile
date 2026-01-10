build:
    gleam run -m build

dev:
    BLOG_ENV=dev gleam run -m build

watch:
    find src/ build/ assets/ | entr -d just dev
