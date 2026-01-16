build:
    gleam run -m build

dev:
    npm run build
    BLOG_ENV=dev gleam run -m build

watch:
    find src/ assets/ -type f | entr -d just dev

export djot_file:
    #!/usr/bin/env bash
    set -euo pipefail

    tmp="$(mktemp -t djot.XXXXXX).pdf"

    npx --yes @djot/djot -t pandoc "{{djot_file}}" \
    | pandoc -f json -s -t typst \
    | typst compile - "$tmp"

    open "$tmp"
