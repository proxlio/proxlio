# Contributing to Proxlio

Thanks for your interest. Proxlio is a small project with a focused scope —
contributions that stay within that scope are very welcome.

## Ways to contribute

**Report a bug** — Open an issue using the bug report template. Include your
OS, Docker version, and the relevant logs (`docker compose logs`). The more
context, the faster we can help. Look for issues tagged `good first issue` for
a low-risk entry point if you're new to the project.

**Propose a feature** — Open an issue using the feature request template before
writing any code. Features that add new Docker components (new services,
sidecars, etc.) need a discussion first — see scope below.

**Submit code** — Fork, branch from `main`, open a PR. Keep changes focused.
One thing per PR.

## Dev setup

```bash
git clone https://github.com/proxlio/proxlio.git
cd proxlio
cp .env.example .env        # fill in your domain and email
docker compose up -d
```

After startup, the services are available at:
- NPM admin UI: `http://localhost:81` (default credentials: `admin@example.com` / `changeme`)
- AdGuard Home: `http://localhost:3000`

## Commit convention

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` new functionality
- `fix:` bug fix
- `docs:` documentation only
- `test:` tests only
- `chore:` maintenance (deps, CI, etc.)

Examples: `fix: handle missing DOMAIN env var`, `feat: add AdGuard DNS rewrite UI`

## Pull requests

- Branch from `main`, name it something meaningful (`fix/wizard-crash`, `feat/auto-renew`)
- PR description: what it does, why it's needed, how to test it
- Keep it small — large PRs are hard to review and slow to merge

## Project scope

Proxlio installs and wires up three things: NPM, AdGuard Home, and a Cloudflare
Tunnel. That's the core.

**In scope:** bug fixes, UX improvements to the wizard, better defaults,
documentation, CI, tests.

**Out of scope (open an issue first):** adding new Docker services, changing the
default stack, integrating third-party tools. These need a design discussion
before any code is written.

If you're unsure whether something fits, open an issue and ask.
