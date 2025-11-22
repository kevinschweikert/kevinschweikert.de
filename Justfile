compile_templates:
    matcha

build: compile_templates
    gleam run -m build
