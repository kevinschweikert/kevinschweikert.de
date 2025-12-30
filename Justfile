build:
    gleam run -m build

watch:
    git ls-files | entr -d just build
