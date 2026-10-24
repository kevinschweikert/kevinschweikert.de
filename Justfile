tailwind:
    npm run build:prod
    
build: tailwind
    gleam run -m build

dev:
    npm run build
    BLOG_ENV=dev SITE_URL=http://localhost:8080 gleam run -m build

watch:
    find src/ assets/ -type f | entr -d just dev

deploy server: build
    rsync -avz --delete --no-perms --no-owner --no-group --omit-dir-times priv/ {{server}}:/opt/caddy/static/blog/
    rsync -avz --no-perms --no-owner --no-group --omit-dir-times caddy/ {{server}}:/opt/caddy/sites/
    ssh {{server}} sudo podman exec caddy caddy reload --config /etc/caddy/Caddyfile
