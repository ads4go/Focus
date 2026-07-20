# Focus

A personal GTD-style task manager for macOS, similar to OmniFocus 4. Inbox,
Projects, Tasks, Tags, due/defer dates, flags, and built-in Inbox / Today /
Flagged / Projects perspectives. Syncs between two Macs (even signed into
different Apple IDs) via a shared Supabase account — no iCloud, no CloudKit,
no Apple Developer Program membership required.

## One-time setup

### 1. Install XcodeGen (already done if you're reading this after the initial build)

```bash
brew install xcodegen
```

### 2. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) and create a free account + new project.
2. In the **SQL Editor**, run the schema below.
3. Under **Authentication → Providers**, confirm Email is enabled.
4. Under **Authentication → Settings**, you can disable "Confirm email" — this
   app is just for your own two Macs, so email confirmation is unnecessary
   friction.
5. Under **Settings -> API**, copy the **Project URL** and **anon public key**.

### 3. Configure secrets

```bash
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

Edit `Config/Secrets.xcconfig` and paste in your Project URL and anon key
(the file is gitignored — never commit real credentials).

### 4. Generate and build

```bash
xcodegen generate
open Focus.xcodeproj
```

Build and run (⌘R). On first launch you'll see a sign-in screen — create an
account with any email/password. **Use the same email/password on both
Macs** — that's what makes them sync to each other, completely independent
of which Apple ID each Mac is signed into.

## Supabase schema

```sql
create table public.tags (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users(id),
  name text not null,
  color_hex text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index tags_owner_updated_idx on public.tags (owner_id, updated_at);

create table public.projects (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users(id),
  name text not null,
  notes text not null default '',
  is_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index projects_owner_updated_idx on public.projects (owner_id, updated_at);

create table public.tasks (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users(id),
  project_id uuid references public.projects(id),
  parent_task_id uuid references public.tasks(id),
  title text not null,
  notes text not null default '',
  due_date timestamptz,
  defer_date timestamptz,
  flagged boolean not null default false,
  completed boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index tasks_owner_updated_idx on public.tasks (owner_id, updated_at);
create index tasks_parent_idx on public.tasks (parent_task_id);

create table public.task_tags (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users(id),
  task_id uuid not null references public.tasks(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index task_tags_owner_updated_idx on public.task_tags (owner_id, updated_at);
create index task_tags_task_idx on public.task_tags (task_id);
create index task_tags_tag_idx on public.task_tags (tag_id);

alter table public.tags enable row level security;
alter table public.projects enable row level security;
alter table public.tasks enable row level security;
alter table public.task_tags enable row level security;

create policy "own rows only" on public.tags for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "own rows only" on public.projects for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "own rows only" on public.tasks for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "own rows only" on public.task_tags for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
```

## Migrations

Schema changes after your initial setup need to be applied by hand in the
Supabase SQL editor — there's no migration runner. So far:

```sql
-- Subtasks (added after initial release)
alter table public.tasks add column parent_task_id uuid references public.tasks(id);
create index tasks_parent_idx on public.tasks (parent_task_id);

-- Nested tag folders (added after initial release)
alter table public.tags add column parent_tag_id uuid references public.tags(id);
create index tags_parent_idx on public.tags (parent_tag_id);

-- Manual drag-to-reorder (added after initial release)
alter table public.tasks add column sort_order integer not null default 0;
alter table public.projects add column sort_order integer not null default 0;
alter table public.tags add column sort_order integer not null default 0;

-- If you previously created sort_order as double precision, convert safely:
alter table public.tasks
  alter column sort_order type integer using round(sort_order)::integer,
  alter column sort_order set default 0,
  alter column sort_order set not null;

alter table public.projects
  alter column sort_order type integer using round(sort_order)::integer,
  alter column sort_order set default 0,
  alter column sort_order set not null;

alter table public.tags
  alter column sort_order type integer using round(sort_order)::integer,
  alter column sort_order set default 0,
  alter column sort_order set not null;

-- Project review cadence (added after initial release)
alter table public.projects add column review_interval_days integer;
alter table public.projects add column last_reviewed_at timestamptz;
```

## How sync works

Polling-based, last-write-wins by `updated_at` — no Realtime. A "Sync Now"
toolbar button triggers it manually; it also runs automatically on launch,
when the window becomes active, roughly every 25 seconds while the app is
open, and ~2 seconds after any local edit. Deletes are soft (`deleted_at`),
never hard, so a delete on one Mac always has something to propagate to the
other. See the code comments in `Sources/Sync/SyncEngine.swift` and
`Sources/Queries/Mutations.swift` for the full rationale, including the one
accepted limitation: two different fields edited concurrently on the same
row during a long offline window resolve last-write-wins at the row level,
not the field level. Fine for a single-user, two-device personal tool; not a
general-purpose CRDT.

## Regenerating the Xcode project

The `.xcodeproj` is gitignored and generated from `project.yml`. After
pulling changes or editing `project.yml`, run:

```bash
xcodegen generate
```

## Project structure

```
Sources/
  App/       — app entry point, root view, sign-in gate
  Models/    — SwiftData models (flat foreign keys, no @Relationship — see Mutations.swift)
  Queries/   — perspective filtering + all local mutations (soft-delete cascades, tag add/remove)
  Sync/      — Supabase client, DTOs, sync cursors, the sync engine, auth session store
  Views/     — SwiftUI views
```
