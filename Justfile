build:
    gleam run -m build

dev:
    npm run build
    BLOG_ENV=dev gleam run -m build

watch:
    find src/ assets/ -type f | entr -d just dev

deploy: build
    rsync -avz --delete --no-perms --no-owner --no-group --omit-dir-times priv/ margherita:/opt/caddy/static/blog/
