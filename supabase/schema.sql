create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  timezone text,
  created_at timestamptz not null default now()
);

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text,
  content text not null,
  entry_date date not null,
  images text[] not null default '{}',
  type text,
  score int not null default 0,
  is_private boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  content_search tsvector generated always as (
    to_tsvector('simple', coalesce(title,'') || ' ' || coalesce(content,''))
  ) stored,
  constraint notes_score_range check (score >= 0 and score <= 5)
);

create index notes_user_date_idx on public.notes(user_id, entry_date desc);
create index notes_privacy_idx on public.notes(is_private);
create index notes_search_idx on public.notes using gin(content_search);
create index notes_type_idx on public.notes(type);

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  unique(user_id, name)
);

create table public.note_tags (
  note_id uuid not null references public.notes(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  primary key(note_id, tag_id)
);

create view public.day_counts as
  select user_id, entry_date, count(*) as cnt
  from public.notes
  where deleted_at is null
  group by user_id, entry_date;

alter table public.notes enable row level security;
alter table public.tags enable row level security;
alter table public.note_tags enable row level security;
alter table public.profiles enable row level security;

create policy profiles_owner_select on public.profiles
  for select using (auth.uid() = id);
create policy profiles_owner_modify on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

create policy notes_owner_select on public.notes
  for select using (auth.uid() = user_id);
create policy notes_public_select on public.notes
  for select using (is_private = false);
create policy notes_owner_write on public.notes
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy tags_owner_all on public.tags
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy note_tags_owner_all on public.note_tags
  for all using (
    exists (
      select 1 from public.notes n where n.id = note_tags.note_id and n.user_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.notes n where n.id = note_tags.note_id and n.user_id = auth.uid()
    )
  );
