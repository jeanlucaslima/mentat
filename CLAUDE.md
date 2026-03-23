# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mentat is an Elixir/Phoenix 1.8 web application using LiveView 1.1, Ecto with PostgreSQL, Tailwind CSS v4, and esbuild. It uses Bandit as the HTTP server.

## Tool Preferences

- Use `rg` (ripgrep) instead of `grep` for all file searches
- Use `fd` instead of `find` for all file finding

## Common Commands

- `mix setup` — install deps, create DB, run migrations, build assets
- `mix phx.server` — start dev server at localhost:4000
- `iex -S mix phx.server` — start dev server with interactive shell
- `mix test` — run all tests (auto-creates/migrates DB)
- `mix test test/path/to/test.exs` — run a single test file
- `mix test test/path/to/test.exs:LINE` — run a specific test
- `mix test --failed` — re-run previously failed tests
- `mix precommit` — compile (warnings-as-errors), unlock unused deps, format, test. **Run this before committing.**
- `mix ecto.gen.migration migration_name` — generate a new migration
- `mix ecto.migrate` — run pending migrations
- `mix ecto.reset` — drop, create, migrate, seed

## Architecture

- **`lib/mentat/`** — business logic (contexts, schemas, repo)
- **`lib/mentat_web/`** — web layer (router, controllers, LiveViews, components)
  - `components/core_components.ex` — shared UI components (`<.input>`, `<.icon>`, `<.form>`, etc.)
  - `components/layouts.ex` — app layout; `<Layouts.app>` wraps all LiveView templates
  - `mentat_web.ex` — macros/imports for controllers, LiveViews, components; `Layouts` is aliased here
- **`assets/`** — JS (`app.js`) and CSS (`app.css`); only these two bundles are supported
- **`config/`** — environment configs; `runtime.exs` for production secrets

## Key Conventions (from AGENTS.md)

### Phoenix 1.8 / LiveView
- LiveView templates must start with `<Layouts.app flash={@flash} ...>`
- Use `<.icon name="hero-x-mark">` for icons (never Heroicons modules)
- Use `<.input>` from core_components for form inputs
- Use `to_form/2` to create forms; never pass changesets directly to templates
- Use LiveView streams for collections (not plain list assigns)
- Avoid LiveComponents unless strongly needed
- Colocated JS hooks use `:type={Phoenix.LiveView.ColocatedHook}` and names prefixed with `.`
- Never write inline `<script>` tags in HEEx templates
- `<.flash_group>` only in `layouts.ex`

### Tailwind CSS v4
- Uses `@import "tailwindcss" source(none)` syntax in `app.css` (no `tailwind.config.js`)
- Never use `@apply`; write Tailwind classes directly
- Write custom components instead of using daisyUI

### Elixir
- Use `Req` for HTTP requests (already a dependency); avoid httpoison/tesla/httpc
- No index-based list access (`list[i]`); use `Enum.at/2`
- No nested modules in the same file
- No map access syntax on structs; use `struct.field` or APIs like `Ecto.Changeset.get_field/2`
- Predicate functions end with `?` (not `is_` prefix, except guards)

### Ecto
- Always preload associations accessed in templates
- `:text` columns use `:string` type in schemas
- Fields set programmatically (e.g. `user_id`) must not be in `cast` calls
- Use `mix ecto.gen.migration` to generate migrations (never create manually)

### Testing
- Use `start_supervised!/1` for process cleanup
- Use `Process.monitor/1` + `assert_receive {:DOWN, ...}` instead of `Process.sleep`
- Use `LazyHTML` for HTML assertions; test against element IDs, not raw HTML
- Use `Phoenix.LiveViewTest` functions (`render_submit/2`, `render_change/2`, `element/2`, `has_element?/2`)

### HEEx Templates
- Use `{...}` for attribute interpolation; `{@assign}` for body values
- Use `<%= ... %>` only for block constructs (if/cond/case/for) in tag bodies
- Use `phx-no-curly-interpolation` for literal curly braces in code blocks
- Class lists must use `[...]` syntax for conditional classes
- Comments: `<%!-- comment --%>`
- Never use `<% Enum.each %>`; always use `:for` or `<%= for ... do %>`
