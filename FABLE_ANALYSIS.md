# FABLE ANALYSIS — Teddy Stack (Axum) vs Supabase: Gap Analysis & Roadmap to Self-Hosting

> **Purpose of this document.** Written in a parallel Claude Code session (2026-06-10) for the
> session running on the Mac that is working on `teddy-stack`. It is a comprehensive audit
> checklist + roadmap for getting the self-hosted Axum/teddy-stack backend to **Supabase parity
> or better**, hosted on **AWS Lightsail**, so the monthly Supabase bill (~$50 AUD/USD) goes to $0
> and every project in the org runs on owned infrastructure.
>
> **Scope caveat:** this session could only read `mah-stack-starter` directly (GitHub access for
> the session was scoped to this repo). `teddy-stack` itself was identified via its repo metadata:
> *"Axum / teddy-stack — local self-hosted Supabase-compatible backend (postgres, gotrue,
> postgrest, storage, realtime, kong, edge runtime). Pre-Lightsail dev mirror lives on TeddyBot."*
> Everything below is therefore structured as a **verify-then-close checklist**: the resuming
> session should tick each item against the actual teddy-stack code and close the gaps in
> priority order.

---

## 1. Context: the Teddy stack today

### 1.1 The bill that triggered this

Supabase Pro is **$25/month per org** + usage. Paid plans include a $10/mo compute credit
(covers one Micro instance); a Small compute instance adds ~$15/mo, Medium adds ~$50/mo.
Bandwidth overage is $0.09/GB. A ~$50 charge is almost certainly one of:

- Pro plan ($25) + Small compute add-on (~$15) + small overages, or
- Pro plan + a **second project** (each extra project burns its own compute, only one $10 credit), or
- Pro plan + egress/MAU overage.

**Action for resuming session:** pull the actual Supabase invoice breakdown (Dashboard →
Organization → Billing → Usage) and record *which* line items cost money. That tells you which
subsystem (compute, egress, storage, MAU) your replacement must size for. Don't cancel anything
until the migration cutover checklist (§7) is green.

### 1.2 Repos in the org that consume (or will consume) the backend

| Repo | What it is | Backend dependency |
|---|---|---|
| `teddy-stack` | **The replacement.** Rust/Axum, self-hosted Supabase-compatible stack (postgres, gotrue, postgrest, storage, realtime, kong, edge runtime). Dev mirror on TeddyBot, target = Lightsail. | n/a — it *is* the backend |
| `mah-stack-starter` (this repo) | Public template: static HTML + supabase-js v2 via esm.sh, Cloudflare Pages, magic-link auth, 2 migrations with RLS | `supabase.from()`, `auth.signInWithOtp`, `auth.getUser` |
| `melbourne-ai-hub` | MAH community site — built on the same pattern as this starter | Same shape as starter: auth + Postgres + RLS |
| `teddys-cleaning-backend` | TypeScript backend for the cleaning app | Likely Supabase or direct PG — audit |
| `command-centre` | Real-time ops dashboard | "Real-time" ⇒ likely Supabase Realtime subscriptions — audit |
| `tcs-web-app`, `teddyscleaningwebsite`, `tcs-shopify` | Cleaning business front-ends | Audit for supabase-js usage |
| `lifeos`, `lifeos-app`, `lifeos-website` | LifeOS suite | Audit |
| `zeroclaw`, `federation` | Rust AI-assistant infra / multi-agent infra | Potential co-tenants on the same Lightsail box |

**Action:** `grep -r "supabase" --include='*.{ts,tsx,js,html}' -l` across each repo on the Mac;
build the definitive consumer list with the exact API surface each one uses. The starter's
surface (verified in this repo) is the minimum bar:

- `POST /auth/v1/otp` (magic link) and `GET /auth/v1/user` — via `signInWithOtp` / `getUser`
- `GET /rest/v1/members?select=id` with `count=exact, head=true` — PostgREST head-count
- `INSERT` into `eoi_submissions` as `anon` role
- JWT roles `anon`, `authenticated`, `service_role`; RLS policies using `auth.uid()`
- Postgres trigger on `auth.users` insert (`handle_new_user`)

### 1.3 The two-track reality of "Supabase-compatible"

teddy-stack's description says it runs the actual Supabase OSS components (gotrue, postgrest,
storage-api, realtime, kong, edge-runtime) **and** is an Axum project. That implies the sensible
hybrid strategy, which this analysis endorses:

- **Track A (parity, fast):** run the Supabase OSS docker-compose stack as-is. Every supabase-js
  client works unchanged — only `SUPABASE_URL`/`SUPABASE_ANON_KEY` change. This is how you kill
  the bill *this month*.
- **Track B (better, incremental):** the Axum binary sits beside (eventually in front of) the
  OSS components and replaces them one at a time where Rust gives a real win (gateway, storage,
  realtime, functions). Keep wire-compatibility with supabase-js at every step so front-ends
  never know.

---

## 2. Full Supabase feature inventory (the parity bar)

Everything Supabase Cloud gives you, grouped by whether the OSS stack covers it. This is the
checklist to audit teddy-stack against.

### 2.1 Covered by the OSS components (verify each is wired and configured)

**Database (Postgres)**
- [ ] Postgres 15/16 with extensions: `pgcrypto`, `pgjwt`, `uuid-ossp`, `pg_net`, `pg_cron`,
      `pgvector` (needed if any AI feature stores embeddings — zeroclaw/federation likely want this)
- [ ] `auth`, `storage`, `realtime` schemas provisioned; roles `anon`, `authenticated`,
      `service_role`, `supabase_admin` exist with correct grants
- [ ] RLS works end-to-end with JWT claims (`request.jwt.claims` → `auth.uid()`)
- [ ] Connection pooling — Supavisor or PgBouncer. **Critical on a small Lightsail box**; raw
      Postgres connections will exhaust memory fast
- [ ] `pg_cron` for scheduled jobs (Supabase Cloud exposes this; you need it for digest emails,
      cleanup jobs)

**Auth (GoTrue)**
- [ ] Email magic link / OTP (`signInWithOtp`) — the starter's only auth method, so P0
- [ ] Email+password, phone OTP (if any app uses it — audit)
- [ ] OAuth providers (Google/GitHub/Apple) — audit which apps use social login
- [ ] JWT issuance with same claim shape supabase-js expects (`sub`, `role`, `email`, `aud`)
- [ ] Refresh-token rotation, session revocation
- [ ] **SMTP** — this is the big config gap when self-hosting. Supabase Cloud's built-in mailer
      goes away. Wire **AWS SES (ap-southeast-2)** — the starter's `.env.example` already
      anticipates this. Without SMTP, magic links silently don't send.
- [ ] Email templates (confirm, magic link, recovery, invite) customized per site
- [ ] Redirect-URL allowlist per consuming site (starter uses `window.location.origin`)
- [ ] Triggers on `auth.users` fire (the starter's `handle_new_user` depends on this)

**REST API (PostgREST)**
- [ ] Full supabase-js `.from()` query grammar: select/insert/upsert/update/delete, filters,
      `count=exact` + `head:true` (the starter's health check uses exactly this), range headers,
      embedded resources (`select=*,other_table(*)`)
- [ ] RPC (`.rpc()`) for Postgres functions
- [ ] `db-schema` config exposing `public` (and any other schemas apps use)

**Realtime**
- [ ] Postgres CDC (`postgres_changes`) — command-centre's live dashboard almost certainly needs this
- [ ] Broadcast + Presence channels
- [ ] WebSocket auth via the same JWTs; RLS-respecting change feeds (`WALRUS`)

**Storage (storage-api)**
- [ ] Buckets, public/private objects, RLS-based access policies
- [ ] Signed URLs, signed upload URLs
- [ ] Image transformations (Supabase Cloud uses imgproxy — run imgproxy container, or this is a
      good Axum-native replacement candidate)
- [ ] Resumable uploads (TUS) if any app uploads large files

**Edge Functions (edge-runtime)**
- [ ] Deno-compatible runtime for existing functions (the starter mentions a Stripe webhook stub)
- [ ] Secrets injection (`SUPABASE_SERVICE_ROLE_KEY`, `OPENROUTER_API_KEY`)
- [ ] **Better-than option:** new server-side logic goes in Axum handlers (native, no cold start,
      typed) and only legacy Deno functions stay on edge-runtime until ported

**Gateway (Kong)**
- [ ] Routes `/auth/v1`, `/rest/v1`, `/realtime/v1`, `/storage/v1`, `/functions/v1` exactly as
      supabase-js expects, with apikey header handling
- [ ] CORS for all consuming domains (`*.pages.dev`, melbourneaihub.com.au, etc.)
- [ ] **Better-than option:** replacing Kong with the Axum binary as gateway is the highest-value
      Rust rewrite — one static binary, removes a JVM-less-but-heavy Lua/nginx container, frees
      ~300–500 MB RAM on the Lightsail box, and gives you a single place for rate limiting,
      logging, and API keys

### 2.2 NOT in the OSS stack — must be built/added (the real gap list)

These are what people actually miss when they leave Supabase Cloud. **This is the core of
"what's missing to be Supabase."**

| # | Supabase Cloud feature | Self-host replacement | Effort | Priority |
|---|---|---|---|---|
| 1 | **Managed backups + PITR** | `pg_dump` nightly → S3/Lightsail object storage + WAL-G or pgBackRest for point-in-time recovery; Lightsail instance snapshots | Medium | **P0 — do before any prod traffic** |
| 2 | **Studio dashboard** | Run `supabase/studio` container (OSS, works self-hosted) behind auth; or accept psql + a SQL client | Low | P1 |
| 3 | **Transactional email infra** | AWS SES + verified domain + DKIM/SPF/DMARC. Cloud Supabase hides this entirely | Low-Med | **P0 — auth is broken without it** |
| 4 | **TLS, domain, cert renewal** | nginx or Caddy (Caddy = auto-TLS, less config) in front; `api.teddystack.com` style subdomain | Low | **P0** |
| 5 | **Observability** (logs UI, query perf, API analytics — Supabase uses Logflare) | Start simple: `docker logs` + journald + Netdata or Prometheus/Grafana single-box; pg_stat_statements for query perf | Medium | P1 |
| 6 | **Migrations tooling/CI** | Keep `supabase` CLI pointed at self-host, or sqlx-migrate / refinery from the Axum side; CI step that applies migrations on deploy | Low | P1 |
| 7 | **Branching / preview environments** | Honest answer: skip. A second docker-compose project on TeddyBot is your staging env | — | P3 |
| 8 | **Uptime, failover, multi-AZ** | Lightsail = one box. Mitigate: snapshots, restore-runbook, UptimeRobot/healthchecks.io alerts, documented RTO. Accept single-node risk consciously | Medium | P1 |
| 9 | **Security patching of components** | You own upgrades now. Pin image versions; monthly `docker compose pull` ritual; subscribe to supabase/gotrue + postgrest release feeds | Ongoing | P1 |
| 10 | **Rate limiting / abuse protection** (Cloud has per-endpoint auth rate limits + captcha hooks) | Axum gateway middleware (tower `RateLimitLayer` / governor crate) — *better than* Supabase here because fully customizable | Low-Med | P1 (anon insert endpoints like `eoi_submissions` are spam magnets) |
| 11 | **Secrets management** | `.env` on box (chmod 600) or AWS SSM Parameter Store; never in repo | Low | P0 |
| 12 | **MAU-scale auth** | Non-issue at current scale; GoTrue self-hosted has no MAU caps — this is where self-hosting is strictly *better* (Cloud charges $0.00325/MAU past 100K) | — | — |

### 2.3 "Better than Supabase" — where the Axum stack can win

1. **Single typed gateway.** Axum replaces Kong: per-route rate limits, structured tracing
   (`tracing` + OTLP), API-key tiers for your own multi-tenant use (every org repo = a tenant).
2. **Native server functions.** Axum handlers instead of Deno cold starts: the Stripe webhook,
   OpenRouter AI proxy, bot endpoints, newsletter pipeline — all compiled, all in one binary.
3. **No metering anxiety.** Flat Lightsail cost regardless of MAU/egress (within instance limits).
4. **Co-tenancy.** zeroclaw/federation (already Rust) can share the box and talk to Postgres on
   localhost — zero-latency, zero egress cost between services. Supabase can't do this at all.
5. **pgvector + AI-first schema** without compute-tier upsell.
6. **Owned data, AU residency** (Lightsail ap-southeast-2, Sydney) — relevant for cleaning-business
   customer data.

---

## 3. Lightsail deployment plan

### 3.1 Sizing

The full OSS stack (postgres + gotrue + postgrest + realtime + storage + kong + edge-runtime +
studio) idles around 2–3 GB RAM. Recommendation:

- **$24/mo plan: 4 GB RAM, 2 vCPU, 80 GB SSD** — comfortable for the full stack + Axum binary.
- $12/mo (2 GB) is possible **only if** Kong→Axum and edge-runtime→Axum replacements land first
  and you skip Studio. Good Track-B milestone: "stack fits in 2 GB".
- Replacing Supabase Pro ($25+) with the $24 Lightsail plan ≈ break-even on dollars but removes
  all overage risk; hitting the $12 plan halves the bill. Lightsail includes generous transfer
  (4–5 TB) vs $0.09/GB Supabase egress.

### 3.2 Box setup checklist

- [ ] Lightsail Ubuntu 24.04 LTS, **static IP** attached, ap-southeast-2
- [ ] Firewall: only 22 (key-only, ideally IP-restricted), 80, 443. **Postgres 5432 NOT exposed**
      — if remote SQL needed, SSH tunnel or Tailscale
- [ ] Docker + compose plugin; stack as a compose project with pinned image tags
- [ ] Caddy (or nginx+certbot) terminating TLS for `api.<domain>` → Kong/Axum
- [ ] Automatic Lightsail snapshots ON (daily) + §2.2-#1 pg-level backups (snapshots alone are
      not PITR)
- [ ] fail2ban + unattended-upgrades
- [ ] Healthcheck endpoint (`/health` on Axum) wired to UptimeRobot/healthchecks.io with phone alert
- [ ] Restore drill performed once before cutover: fresh box + latest backup → working stack < 1 hr

### 3.3 TeddyBot → Lightsail promotion path

TeddyBot (local dev mirror) stays the staging environment. Promotion = same compose file, same
pinned tags, different `.env`. Keep one `deploy/` directory in teddy-stack with
`compose.yml`, `Caddyfile`, `.env.example`, and a `release.sh` (this starter repo already has the
Tier-1.5 VPS pattern: `release.sh` + nginx template + `docs/tier-2-vps.md` per its README —
reuse that shape).

---

## 4. Migration plan for consuming apps

Because Track A keeps wire-compatibility, migration per app is:

1. Apply that app's migrations to teddy-stack Postgres (this repo: `supabase/migrations/0001`,
   `0002` — they're idempotent, run in order; note `0001` creates a trigger **on `auth.users`**,
   so GoTrue's schema must exist first).
2. Configure GoTrue redirect allowlist + email templates for that app's domain.
3. Change two env vars in the host (Cloudflare Pages): `SUPABASE_URL` → `https://api.<domain>`,
   `SUPABASE_ANON_KEY` → teddy-stack's anon JWT. Redeploy.
4. Verify: health badge "connected ✓", magic-link round-trip lands in inbox (SES), signs in,
   `members` row auto-created, EOI form inserts as anon, tier2 user can read EOI list.
5. Export/import existing data: `auth.users` must be migrated with password hashes & identities
   (GoTrue-compatible — use supabase's official `pg_dump` of `auth` schema), then public tables.

Order: **mah-stack-starter (lowest risk, public template) → melbourne-ai-hub → command-centre
(validates realtime) → cleaning-business apps (highest stakes, last).**

Only after all apps are cut over and stable for ~2 weeks: downgrade/cancel Supabase Pro.

---

## 5. Prioritized roadmap (for the resuming session)

**P0 — "can take real traffic" (target: this week)**
1. Audit teddy-stack against §2.1 — record which components run & versions
2. SES domain verification + GoTrue SMTP → magic-link e2e test
3. Caddy/TLS + domain on TeddyBot mirror (then Lightsail)
4. Backup pipeline (pgBackRest or WAL-G → object storage) + one restore drill
5. Secrets out of any tracked files

**P1 — "operable" (target: ~2 weeks)**
6. Lightsail box provisioned per §3.2; promote stack
7. Migrate mah-stack-starter + melbourne-ai-hub (per §4)
8. Rate limiting on `/auth/v1/otp` + anon inserts
9. Monitoring + alerting + pinned-image upgrade ritual
10. Studio (or chosen SQL UI) behind auth

**P2 — "better than Supabase" (Track B, ongoing)**
11. Axum gateway replaces Kong (rate limits, tracing, API keys)
12. New server logic as Axum handlers; port Deno functions opportunistically
13. Realtime validation under command-centre load; pgvector for AI features
14. Fit-in-2GB milestone → consider downsizing to $12 Lightsail plan

**P3 — nice-to-have**
15. Preview-env story, read replica, multi-box failover — only if scale demands

---

## 6. Acceptance criteria for "Supabase parity or better"

- [ ] Every supabase-js call made by every org app works against teddy-stack unchanged
- [ ] Magic-link auth delivers email in <30 s via SES on all sites
- [ ] RLS verified: anon cannot read `eoi_submissions`; users only see own `members` row
- [ ] Realtime subscription drives command-centre live updates
- [ ] Nightly backups verified by an actual restore, documented RTO ≤ 1 hour
- [ ] Uptime alerting fires on kill-test of any container
- [ ] Monthly infra cost ≤ $24 (stretch: ≤ $12) with zero usage-based line items
- [ ] Supabase Cloud subscription cancelled

---

*Sources for pricing figures: [supabase.com/pricing](https://supabase.com/pricing),
[UI Bakery Supabase pricing breakdown (2026)](https://uibakery.io/blog/supabase-pricing),
[Toolradar Supabase pricing 2026](https://toolradar.com/blog/supabase-pricing-2026).*
