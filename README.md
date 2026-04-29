# mah-stack-starter

A minimal MAH-pattern starter for founders building their own stack.

**What you get** when you fork this template:

- Static HTML + vanilla JS frontend (no build step, no bundler)
- Supabase backend (Postgres + Auth + Edge Functions)
- Cloudflare Pages auto-deploy on every git push
- Magic-link sign-in wired and ready
- Row-level-security skeleton you can extend

**Not included** (intentionally — keeps the starter slim):

- A bot
- A newsletter pipeline
- Stripe wiring beyond a webhook stub
- A VPS deploy path (the appendix `docs/tier-2-vps.md` covers it; not
  needed for v1)

## Use this template

Click the green **"Use this template"** button at the top of this page
on GitHub, choose **"Create a new repository"**, name it whatever you
want.

That's the start. Everything else is in the handbook.

## The handbook

The step-by-step guide for setting this up — including signups, the
Supabase project, Cloudflare Pages, your first edit, and magic-link
auth — lives at:

> <https://melbourneaihub.com.au/slides/founder-stack-starter-handbook.pdf>

It is also the canonical reference for what this repo is for, who
built it, and where to ask questions.

## Quick start, no handbook

For founders who already know what they're doing:

1. Use this template → name your repo.
2. Create a Supabase project (free tier, no card).
3. In Cloudflare Pages: Connect to Git → your fork → set
   `SUPABASE_URL` and `SUPABASE_ANON_KEY` env vars → Deploy.
4. Set Site URL + Redirect URLs in Supabase Auth → URL Configuration
   to your `*.pages.dev` URL.
5. Run the migrations in `supabase/migrations/` against your project
   via the SQL editor.

You'll have a live full-stack site in ~30 min.

## Tier 2 — contribute to MAH

If you've shipped Tier 1 and want to contribute to Melbourne AI Hub
itself, see the manual review flow at chapter 08 of the handbook.

## Tier 1.5 — your own VPS

The repo includes the files for a VPS deploy too: `release.sh`,
`nginx/sites-available/template.conf`, and `docs/tier-2-vps.md`. They
are **not required** for the Cloudflare Pages path. They're there for
when you want to learn what `nginx` and `certbot` actually do.

## Provenance + licence

This starter is maintained by Melbourne AI Hub. The MAH community runs
on the same architectural shape this template provides.

Code under this repo is licensed permissively (see `LICENSE`).
Use it for whatever you want; attribution appreciated, not required.

## Issues + improvements

If you hit something the handbook doesn't cover, drop a note in the
MAH Telegram group or open an issue on this repo. Fixes welcome.
