create table if not exists public.portal_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users (id) on delete restrict,
  actor_email text not null,
  application_id text not null,
  application_name text not null,
  event_type text not null,
  success boolean not null default true,
  failure_code text,
  platform text,
  app_version text,
  device_hash text,
  session_id text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default timezone('utc', now())
);

create index if not exists portal_audit_logs_occurred_at_idx
  on public.portal_audit_logs (occurred_at desc);
create index if not exists portal_audit_logs_actor_email_occurred_at_idx
  on public.portal_audit_logs (actor_email, occurred_at desc);
create index if not exists portal_audit_logs_application_occurred_at_idx
  on public.portal_audit_logs (application_id, occurred_at desc);

alter table public.portal_audit_logs enable row level security;
revoke all on table public.portal_audit_logs from anon;
grant insert, select on table public.portal_audit_logs to authenticated;

drop policy if exists "authenticated users can record their own portal events"
  on public.portal_audit_logs;
create policy "authenticated users can record their own portal events"
  on public.portal_audit_logs for insert to authenticated
  with check (
    actor_id = (select auth.uid())
    and lower(actor_email) = lower(coalesce((select auth.jwt() ->> 'email'), ''))
  );

drop policy if exists "only portal admins can read audit logs"
  on public.portal_audit_logs;
create policy "only portal admins can read audit logs"
  on public.portal_audit_logs for select to authenticated
  using (
    lower(coalesce((select auth.jwt() ->> 'email'), '')) in (
      'karaba@firesidefoundation.org',
      'joseph.n@fireside.africa'
    )
  );
