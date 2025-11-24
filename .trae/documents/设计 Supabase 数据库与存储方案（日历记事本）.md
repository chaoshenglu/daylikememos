## 概述
- 目标：为“日历记事本”构建全新 Supabase 数据库与存储设计，支持图片上传、笔记类型与评分，并能按日统计与搜索。
- 组成：Auth 用户、笔记、标签、日级统计视图、私有 Storage Bucket。

## 实体与关系
- 用户资料 `profiles` 1:n 笔记 `notes`
- 笔记可 n:n 标签（`tags` 与 `note_tags`）
- 图片统一保存在 Storage，笔记的图片路径保存在 `notes.images`

## 表设计
### profiles
- 用途：保存用户显示名、头像与时区
- 字段：
  - `id uuid` 主键，引用 `auth.users(id)`
  - `display_name text`
  - `avatar_url text`
  - `timezone text`
  - `created_at timestamptz` 默认 `now()`

### notes
- 用途：用户日记内容，支持图片、类型、评分与隐私
- 字段：
  - `id uuid` 主键，默认 `gen_random_uuid()`
  - `user_id uuid` 引用 `profiles(id)`
  - `title text`
  - `content text` 不为空
  - `entry_date date` 不为空（按用户时区写入）
  - `images text[]` 不为空，默认空数组（存储 Storage 对象路径）
  - `type text`（如 text、photo 等）
  - `score int` 不为空，默认 0，范围 0–5
  - `is_private boolean` 不为空，默认 `true`
  - `created_at timestamptz` 默认 `now()`
  - `updated_at timestamptz` 默认 `now()`
  - `deleted_at timestamptz`
  - `content_search tsvector` 生成列，用于全文搜索
- 约束：`check (score >= 0 and score <= 5)`

### tags
- 用途：标签字典，用户维度唯一
- 字段：
  - `id uuid` 主键，默认 `gen_random_uuid()`
  - `user_id uuid` 引用 `profiles(id)`
  - `name text` 不为空，`unique(user_id, name)`
  - `created_at timestamptz` 默认 `now()`

### note_tags
- 用途：笔记与标签的关联表
- 字段：
  - `note_id uuid` 引用 `notes(id)`
  - `tag_id uuid` 引用 `tags(id)`
  - 复合主键 `(note_id, tag_id)`

### day_counts 视图
- 用途：供日历显示某天是否有内容与数量
- 列：`user_id`, `entry_date`, `cnt`
- 来源：`notes` 中未删除数据按日聚合

## 索引与搜索
- `notes_user_date_idx` 组合索引 `(user_id, entry_date desc)`
- `notes_privacy_idx` 索引 `is_private`
- `notes_search_idx` GIN 索引 `content_search`
- `notes_type_idx` 索引 `type`
- `attachments` 不使用单独表，图片元数据以需求最简方案由前端掌握

## 行级安全（RLS）策略（描述）
- `profiles`：仅本人可读写
- `notes`：本人可读写；他人仅可读公开数据（`is_private=false`）
- `tags` 与 `note_tags`：仅本人可读写

## Storage 设计
- 建立私有 Bucket `note-images`
- 对象路径：`{user_id}/{yyyy}/{mm}/{dd}/{uuid}.{ext}`
- 访问策略：统一使用签名 URL；无公开读权限
- `notes.images` 存储对象路径数组

## 常用交互约定
- 新建笔记：先上传图片到 Storage，拿到对象路径；提交 `notes` 时将路径数组写入 `images`
- 查询某日：按 `entry_date` 过滤并返回 `images`
- 搜索：`content_search` 使用 `plainto_tsquery('simple', q)`

## 初始建表 SQL
```sql
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
```

## 后续实施
- 在 Supabase SQL Editor 中创建上述对象并配置 RLS 与 Storage Bucket
- 前端接 Supabase JS 与日历组件，实现上传、保存与展示流程

若确认该设计，我将基于此开始前端与后端联调实现。