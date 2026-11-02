import { useQuery } from '@tanstack/react-query'
import { formatDistanceToNow } from 'date-fns'
import { Link } from 'react-router-dom'
import { Plus, Users } from 'lucide-react'
import { useAuth } from '../../api/auth'
import { alertApi, dashboardApi, incidentApi, unwrapList } from '../../api/services'
import { ErrorState, LoadingState, PageHeader, StatCard, StatusBadge } from '../../components/ui'

export function OrgDashboard() {
  const { activeOrgId, activeMembership } = useAuth()
  const params = activeOrgId ? { organization: activeOrgId } : undefined
  const summary = useQuery({
    queryKey: ['dashboard', activeOrgId],
    queryFn: async () => (await dashboardApi.summary(params)).data,
    refetchInterval: 5000,
  })
  const alerts = useQuery({
    queryKey: ['alerts-recent', activeOrgId],
    queryFn: async () =>
      unwrapList((await alertApi.list({ ...params, ordering: '-received_at', page_size: '5' })).data),
    refetchInterval: 5000,
  })
  const incidents = useQuery({
    queryKey: ['incidents-recent', activeOrgId],
    queryFn: async () =>
      unwrapList((await incidentApi.list({ ...params, ordering: '-created_at', page_size: '5' })).data),
    refetchInterval: 5000,
  })

  if (summary.isLoading) return <LoadingState />
  if (summary.isError)
    return <ErrorState message="Failed to load dashboard" onRetry={() => summary.refetch()} />
  const s = summary.data!
  const orgName = activeMembership?.organization_name || 'Your organization'

  return (
    <div className="dash-enter space-y-5 sm:space-y-6">
      <PageHeader
        title="Dashboard"
        subtitle={`Plan coverage and respond faster for ${orgName}.`}
        actions={
          <>
            <Link
              to="people"
              className="inline-flex h-11 w-full items-center justify-center gap-2 rounded-xl bg-[var(--color-blue)] px-4 text-sm font-semibold text-white hover:bg-[var(--color-blue-dark)] sm:w-auto"
            >
              <Plus className="h-4 w-4" />
              Manage individuals
            </Link>
            <Link
              to="reports"
              className="inline-flex h-11 w-full items-center justify-center rounded-xl border border-[var(--color-border)] bg-white px-4 text-sm font-semibold text-[var(--color-charcoal)] hover:bg-slate-50 sm:w-auto"
            >
              View reports
            </Link>
          </>
        }
      />

      <section className="dash-enter-delay-1 grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-4">
        <Link to="people" className="block">
          <StatCard
            featured
            label="Individuals"
            value={s.people.total}
            hint="People under your protection"
          />
        </Link>
        <Link to="people" className="block">
          <StatCard label="Bracelets in use" value={s.bracelets.in_use} tone="ok" hint="Active coverage" />
        </Link>
        <StatCard label="Unassigned devices" value={s.bracelets.unassigned} hint="Ready to assign" />
        <Link to="incidents" className="block">
          <StatCard
            label="Open incidents"
            value={s.incidents.open}
            tone={s.incidents.open ? 'danger' : 'default'}
            hint={s.incidents.open ? 'Needs attention' : 'All clear'}
          />
        </Link>
      </section>

      <section className="dash-enter-delay-2 grid gap-4 lg:grid-cols-[1.4fr_1fr]">
        <div className="console-card overflow-hidden">
          <div className="flex items-center justify-between px-5 py-4">
            <div>
              <h2 className="text-base font-semibold text-[var(--color-charcoal)]">Recent alerts</h2>
              <p className="text-sm text-slate-500">Live events from bracelets</p>
            </div>
            <Link
              to="alerts"
              className="rounded-xl bg-slate-50 px-3 py-1.5 text-sm font-semibold text-[var(--color-blue)] hover:bg-slate-100"
            >
              View all
            </Link>
          </div>
          <div className="divide-y divide-[var(--color-border)]">
            {alerts.data?.length ? (
              alerts.data.map((a) => (
                <div
                  key={a.id}
                  className="flex flex-col gap-2 px-5 py-3.5 text-sm sm:flex-row sm:items-center sm:justify-between"
                >
                  <div className="min-w-0">
                    <p className="font-semibold break-words text-[var(--color-charcoal)]">
                      {a.person_name || 'Unassigned'}
                    </p>
                    <p className="text-slate-500">
                      {a.device_id} · {a.alert_code}
                    </p>
                  </div>
                  <div className="flex items-center gap-3 sm:flex-col sm:items-end sm:gap-1">
                    <StatusBadge status={a.alert_code} />
                    <p className="text-xs text-slate-400">
                      {formatDistanceToNow(new Date(a.received_at), { addSuffix: true })}
                    </p>
                  </div>
                </div>
              ))
            ) : (
              <p className="px-5 py-10 text-center text-sm text-slate-500">No alerts yet.</p>
            )}
          </div>
        </div>

        <div className="space-y-4">
          <div className="console-card overflow-hidden">
            <div className="flex items-center justify-between px-5 py-4">
              <div>
                <h2 className="text-base font-semibold text-[var(--color-charcoal)]">Incidents</h2>
                <p className="text-sm text-slate-500">Response queue</p>
              </div>
              <Link
                to="incidents"
                className="rounded-xl bg-slate-50 px-3 py-1.5 text-sm font-semibold text-[var(--color-blue)] hover:bg-slate-100"
              >
                Open
              </Link>
            </div>
            <div className="divide-y divide-[var(--color-border)]">
              {incidents.data?.length ? (
                incidents.data.slice(0, 4).map((i) => (
                  <Link
                    key={i.id}
                    to={`incidents/${i.id}`}
                    className="flex items-start justify-between gap-3 px-5 py-3.5 text-sm hover:bg-slate-50/80"
                  >
                    <div className="min-w-0">
                      <p className="font-semibold text-[var(--color-charcoal)]">
                        {i.person_name || 'Unknown'}
                      </p>
                      <p className="truncate text-slate-500">
                        {i.alert_code} · {i.assigned_responder_email || 'Unassigned'}
                      </p>
                    </div>
                    <StatusBadge status={i.status} />
                  </Link>
                ))
              ) : (
                <p className="px-5 py-10 text-center text-sm text-slate-500">No incidents yet.</p>
              )}
            </div>
          </div>

          <Link
            to="people"
            className="console-card flex items-center gap-4 px-5 py-5 transition hover:border-[var(--color-blue)]/25"
          >
            <span className="inline-flex h-11 w-11 items-center justify-center rounded-2xl bg-[var(--color-blue)]/10 text-[var(--color-blue)]">
              <Users className="h-5 w-5" />
            </span>
            <div className="min-w-0">
              <p className="font-semibold text-[var(--color-charcoal)]">Individuals & bracelets</p>
              <p className="text-sm text-slate-500">
                {s.people.total} people · {s.bracelets.total} devices · add and assign in one place
              </p>
            </div>
          </Link>

          <div className="grid grid-cols-2 gap-3">
            <div className="console-card p-4">
              <p className="text-xs font-semibold uppercase tracking-[0.12em] text-slate-400">
                Alerts (30d)
              </p>
              <p className="mt-2 text-2xl font-semibold text-[var(--color-charcoal)]">
                {s.alerts.last_30_days}
              </p>
            </div>
            <div className="console-card p-4">
              <p className="text-xs font-semibold uppercase tracking-[0.12em] text-slate-400">
                Resolved
              </p>
              <p className="mt-2 text-2xl font-semibold text-[var(--color-charcoal)]">
                {s.incidents.resolved}
              </p>
            </div>
          </div>
        </div>
      </section>
    </div>
  )
}
