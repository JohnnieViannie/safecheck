import {
  keepPreviousData,
  useMutation,
  useQuery,
  useQueryClient,
} from '@tanstack/react-query'
import { Link, useNavigate } from 'react-router-dom'
import {
  Area,
  AreaChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { useEffect, useState } from 'react'
import { getErrorMessage, useAuth } from '../api/auth'
import {
  auditApi,
  authApi,
  dashboardApi,
  orgApi,
  smsApi,
  unwrapList,
  usersApi,
} from '../api/services'
import {
  AdminCard,
  Button,
  ErrorState,
  Input,
  LoadingState,
  Modal,
  PageHeader,
  PasswordInput,
  SearchInput,
  Select,
  SoftStatCard,
  StatusBadge,
} from '../components/ui'
import { AddUserModal } from '../components/AddUserModal'
import { PhoneInput } from '../components/PhoneInput'
import { Avatar } from '../components/PhotoUploader'
import { ProfileEditor } from '../components/ProfileEditor'
import { StaffSection } from '../components/StaffSection'
import { EMPTY_PHONE, isValidEmail, isValidNationalPhone, toE164, type PhoneValue } from '../lib/phone'
import { ReportsPage } from './org/ReportsSettings'
import { AlertsPage } from './org/Alerts'
import { IncidentsPage } from './org/Incidents'
import type { Organization, User } from '../types'
import { toast } from 'sonner'

const PAGE_SIZE = 25

function useDebouncedValue<T>(value: T, delay = 300) {
  const [debounced, setDebounced] = useState(value)
  useEffect(() => {
    const t = window.setTimeout(() => setDebounced(value), delay)
    return () => window.clearTimeout(t)
  }, [value, delay])
  return debounced
}

function CoverageRing({ active, total }: { active: number; total: number }) {
  const inactive = Math.max(total - active, 0)
  const pct = total > 0 ? Math.round((active / total) * 100) : 0
  const data = [
    { name: 'Active', value: active || 0 },
    { name: 'Other', value: inactive || (total === 0 ? 1 : 0) },
  ]
  return (
    <div className="relative mx-auto h-44 w-44">
      <ResponsiveContainer width="100%" height="100%">
        <PieChart>
          <Pie
            data={data}
            dataKey="value"
            innerRadius={58}
            outerRadius={78}
            strokeWidth={0}
            startAngle={90}
            endAngle={-270}
          >
            <Cell fill="#0b5fa5" />
            <Cell fill="#e8eef4" />
          </Pie>
          <Tooltip />
        </PieChart>
      </ResponsiveContainer>
      <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
        <p className="font-display text-3xl text-[var(--color-charcoal)]">{pct}%</p>
        <p className="text-xs text-slate-500">Active devices</p>
      </div>
    </div>
  )
}

function MetricBars({
  items,
}: {
  items: { label: string; value: number; max: number; tone?: 'blue' | 'red' | 'muted' }[]
}) {
  return (
    <div className="space-y-4">
      {items.map((item) => {
        const width =
          item.max > 0 ? Math.max((item.value / item.max) * 100, item.value > 0 ? 6 : 0) : 0
        const bar =
          item.tone === 'red'
            ? 'bg-[var(--color-red)]'
            : item.tone === 'muted'
              ? 'bg-slate-300'
              : 'bg-[var(--color-blue)]'
        return (
          <div key={item.label}>
            <div className="mb-1.5 flex items-center justify-between text-sm">
              <span className="text-slate-600">{item.label}</span>
              <span className="font-semibold text-[var(--color-charcoal)]">{item.value}</span>
            </div>
            <div className="h-3 overflow-hidden rounded-full bg-slate-100">
              <div className={`h-full rounded-full ${bar}`} style={{ width: `${width}%` }} />
            </div>
          </div>
        )
      })}
    </div>
  )
}

function TrendChart({
  title,
  data,
  color,
  gradientId,
}: {
  title: string
  data: { label: string; count: number }[]
  color: string
  gradientId: string
}) {
  return (
    <AdminCard title={title}>
      <div className="h-56 w-full">
        {!data.length ? (
          <p className="flex h-full items-center justify-center text-sm text-slate-400">
            No data yet
          </p>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={data} margin={{ top: 8, right: 8, left: -18, bottom: 0 }}>
              <defs>
                <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={color} stopOpacity={0.35} />
                  <stop offset="100%" stopColor={color} stopOpacity={0.02} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 6" stroke="#e8eef4" vertical={false} />
              <XAxis
                dataKey="label"
                tick={{ fill: '#94a3b8', fontSize: 11 }}
                tickLine={false}
                axisLine={false}
                interval="preserveStartEnd"
                minTickGap={28}
              />
              <YAxis
                allowDecimals={false}
                tick={{ fill: '#94a3b8', fontSize: 11 }}
                tickLine={false}
                axisLine={false}
                width={36}
              />
              <Tooltip
                contentStyle={{
                  borderRadius: 12,
                  border: '1px solid #e2e8f0',
                  boxShadow: '0 8px 24px rgba(15,23,42,0.08)',
                }}
              />
              <Area
                type="monotone"
                dataKey="count"
                stroke={color}
                strokeWidth={2.5}
                fill={`url(#${gradientId})`}
                dot={false}
                activeDot={{ r: 4, strokeWidth: 0 }}
              />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </div>
    </AdminCard>
  )
}

export function AdminOverview() {
  const summary = useQuery({
    queryKey: ['admin-dashboard'],
    queryFn: async () => (await dashboardApi.summary()).data,
    refetchInterval: 15000,
  })
  const birthdays = useQuery({
    queryKey: ['upcoming-birthdays'],
    queryFn: async () => (await usersApi.upcomingBirthdays()).data,
  })
  const orgs = useQuery({
    queryKey: ['admin-orgs-preview'],
    queryFn: async () => unwrapList((await orgApi.list({ page_size: '5' })).data),
  })

  if (summary.isLoading && !summary.data) return <LoadingState />
  if (summary.isError)
    return <ErrorState message={getErrorMessage(summary.error)} onRetry={() => summary.refetch()} />

  const s = summary.data!
  const orgsCount = s.platform?.organizations ?? 0
  const usersCount = s.platform?.users ?? 0
  const individuals = s.platform?.individuals ?? 0
  const maxBar = Math.max(s.alerts.total, s.incidents.total, s.bracelets.total, 1)

  return (
    <div className="mx-auto max-w-7xl space-y-5 sm:space-y-6">
      <div className="dash-enter flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-400">
            Dashboard
          </p>
          <h1 className="mt-1 font-display text-3xl text-[var(--color-charcoal)] sm:text-4xl">
            Platform overview
          </h1>
          <p className="mt-1 text-sm text-slate-500">Global SafeBangle operations at a glance</p>
        </div>
        <Link
          to="/admin/organizations"
          className="inline-flex h-11 items-center justify-center rounded-2xl bg-[var(--color-blue)] px-5 text-sm font-semibold text-white shadow-[0_12px_28px_-14px_rgba(8,74,130,0.7)] hover:bg-[var(--color-blue-dark)]"
        >
          View organizations
        </Link>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-4">
        <div className="dash-enter dash-enter-delay-1 col-span-2 sm:col-span-1">
          <SoftStatCard
            label="Organizations"
            value={orgsCount}
            hint="Active on the platform"
            tone="featured"
            to="/admin/organizations"
          />
        </div>
        <div className="dash-enter dash-enter-delay-1">
          <SoftStatCard label="Users" value={usersCount} hint="All account types" to="/admin/users" />
        </div>
        <div className="dash-enter dash-enter-delay-2">
          <SoftStatCard
            label="Bracelets"
            value={s.bracelets.total}
            hint={`${s.bracelets.active} active`}
            to="/admin/users"
          />
        </div>
        <div className="dash-enter dash-enter-delay-2">
          <SoftStatCard
            label="Open incidents"
            value={s.incidents.open}
            hint={s.incidents.open ? 'Needs attention' : 'All clear'}
            tone={s.incidents.open ? 'danger' : 'default'}
            to="/admin/incidents"
          />
        </div>
      </div>

      <div className="dash-enter dash-enter-delay-3 grid gap-4 lg:grid-cols-3">
        <TrendChart
          title="User growth (12 mo)"
          data={s.user_growth || []}
          color="#0b5fa5"
          gradientId="usersFill"
        />
        <TrendChart
          title="Alerts sent (12 mo)"
          data={s.alerts_over_time || []}
          color="#c2410c"
          gradientId="alertsFill"
        />
        <TrendChart
          title="SMS sent (12 mo)"
          data={s.sms_over_time || []}
          color="#0f766e"
          gradientId="smsFill"
        />
      </div>

      <div className="dash-enter grid gap-4 lg:grid-cols-5">
        <AdminCard title="Operations mix" className="lg:col-span-3">
          <p className="mb-4 text-xs text-slate-400">
            Bars are relative to the largest metric, not a completion percentage.
          </p>
          <MetricBars
            items={[
              { label: 'Alerts', value: s.alerts.total, max: maxBar, tone: 'blue' },
              { label: 'Incidents', value: s.incidents.total, max: maxBar, tone: 'red' },
              { label: 'Bracelets', value: s.bracelets.total, max: maxBar, tone: 'blue' },
              {
                label: 'Resolved incidents',
                value: s.incidents.resolved,
                max: maxBar,
                tone: 'muted',
              },
            ]}
          />
          <div className="mt-5 grid grid-cols-3 gap-3 border-t border-black/[0.04] pt-4 text-center">
            <div>
              <p className="text-xs text-slate-500">Alerts (30d)</p>
              <p className="mt-1 text-lg font-semibold">{s.alerts.last_30_days}</p>
            </div>
            <div>
              <p className="text-xs text-slate-500">In use</p>
              <p className="mt-1 text-lg font-semibold">{s.bracelets.in_use}</p>
            </div>
            <div>
              <p className="text-xs text-slate-500">Individuals</p>
              <p className="mt-1 text-lg font-semibold">{individuals}</p>
            </div>
          </div>
        </AdminCard>

        <AdminCard title="Device coverage" className="lg:col-span-2">
          <CoverageRing active={s.bracelets.active} total={s.bracelets.total} />
          <div className="mt-2 flex justify-center gap-4 text-xs text-slate-500">
            <span className="inline-flex items-center gap-1.5">
              <span className="h-2.5 w-2.5 rounded-full bg-[var(--color-blue)]" /> Active{' '}
              {s.bracelets.active}
            </span>
            <span className="inline-flex items-center gap-1.5">
              <span className="h-2.5 w-2.5 rounded-full bg-slate-200" /> Other{' '}
              {Math.max(s.bracelets.total - s.bracelets.active, 0)}
            </span>
          </div>
        </AdminCard>
      </div>

      <AdminCard title="Upcoming birthdays" className="dash-enter">
        {birthdays.isLoading ? (
          <LoadingState label="Loading birthdays…" />
        ) : birthdays.data?.length ? (
          <ul className="divide-y divide-black/[0.04]">
            {birthdays.data.map((b) => (
              <li key={b.id} className="first:pt-0 last:pb-0">
                <Link
                  to={`/admin/users/${b.id}`}
                  className="flex items-center justify-between gap-3 py-2.5 hover:bg-slate-50/70"
                >
                  <div className="flex min-w-0 items-center gap-2.5">
                    <Avatar name={b.full_name} photoUrl={b.photo_url} size="sm" />
                    <p className="truncate font-semibold text-[var(--color-charcoal)]">{b.full_name}</p>
                  </div>
                  <span className="shrink-0 text-sm text-slate-500">
                    {b.days_away === 0
                      ? 'Today'
                      : b.days_away === 1
                        ? 'Tomorrow'
                        : new Date(`${b.date}T00:00:00`).toLocaleDateString(undefined, {
                            month: 'short',
                            day: 'numeric',
                          })}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        ) : (
          <p className="py-4 text-center text-sm text-slate-500">No birthdays in the next 7 days.</p>
        )}
      </AdminCard>

      <div className="grid gap-4 lg:grid-cols-5">
        <AdminCard
          title="Organizations"
          className="dash-enter lg:col-span-3"
          action={
            <Link
              to="/admin/organizations"
              className="text-sm font-semibold text-[var(--color-blue)] hover:text-[var(--color-blue-dark)]"
            >
              View all
            </Link>
          }
        >
          {orgs.isLoading ? (
            <LoadingState label="Loading organizations…" />
          ) : orgs.data?.length ? (
            <ul className="divide-y divide-black/[0.04]">
              {orgs.data.slice(0, 5).map((o) => (
                <li key={o.id} className="first:pt-0 last:pb-0">
                  <Link
                    to={`/admin/organizations/${o.id}`}
                    className="flex items-center justify-between gap-3 py-3 hover:bg-slate-50/70"
                  >
                    <div className="min-w-0">
                      <p className="truncate font-semibold text-[var(--color-charcoal)]">{o.name}</p>
                      <p className="text-xs text-slate-500">
                        Joined {new Date(o.created_at).toLocaleDateString()}
                      </p>
                    </div>
                    <span className="shrink-0 rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-600">
                      {o.people_count} {o.people_count === 1 ? 'member' : 'members'} · {o.member_count} staff
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          ) : (
            <p className="py-8 text-center text-sm text-slate-500">No organizations yet.</p>
          )}
        </AdminCard>

        <div className="admin-wave dash-enter relative flex flex-col justify-between px-5 py-5 lg:col-span-2">
          <div className="relative z-10">
            <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-blue-100/80">
              Quick links
            </p>
            <p className="mt-2 font-display text-2xl leading-snug">Jump into live operations</p>
          </div>
          <div className="relative z-10 mt-6 grid grid-cols-2 gap-2">
            {[
              { to: '/admin/users', label: 'Users' },
              { to: '/admin/organizations', label: 'Organizations' },
              { to: '/admin/sms', label: 'SMS' },
              { to: '/admin/incidents', label: 'Incidents' },
            ].map((item) => (
              <Link
                key={item.to}
                to={item.to}
                className="rounded-xl bg-white/12 px-3 py-3 text-center text-sm font-semibold text-white ring-1 ring-white/15 transition hover:bg-white/18"
              >
                {item.label}
              </Link>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}

export function AdminOrganizations() {
  const qc = useQueryClient()
  const [search, setSearch] = useState('')
  const debouncedSearch = useDebouncedValue(search)
  const [showInactive, setShowInactive] = useState(false)
  const navigate = useNavigate()
  const [editing, setEditing] = useState<Organization | null>(null)
  const [creating, setCreating] = useState(false)
  const [form, setForm] = useState({
    name: '',
    email: '',
    phone: '',
    address: '',
    description: '',
  })
  const [owner, setOwner] = useState({ first_name: '', last_name: '', email: '' })
  const [ownerPhone, setOwnerPhone] = useState<PhoneValue>(EMPTY_PHONE)
  const [ownerError, setOwnerError] = useState('')

  const query = useQuery({
    queryKey: ['admin-orgs', debouncedSearch],
    queryFn: async () => {
      const { data } = await orgApi.list({ search: debouncedSearch, page_size: '200' })
      return unwrapList(data)
    },
    placeholderData: keepPreviousData,
  })

  const openCreate = () => {
    setCreating(true)
    setEditing(null)
    setForm({ name: '', email: '', phone: '', address: '', description: '' })
    setOwner({ first_name: '', last_name: '', email: '' })
    setOwnerPhone((p) => ({ ...p, national: '' }))
    setOwnerError('')
  }

  const openEdit = (org: Organization) => {
    setEditing(org)
    setCreating(false)
    setForm({
      name: org.name || '',
      email: org.email || '',
      phone: org.phone || '',
      address: org.address || '',
      description: org.description || '',
    })
  }

  const saveOrg = useMutation({
    mutationFn: async () => {
      const payload = {
        name: form.name.trim(),
        email: form.email.trim(),
        phone: form.phone.trim(),
        address: form.address.trim(),
        description: form.description.trim(),
      }
      if (editing) {
        await orgApi.update(editing.id, payload)
        return null
      }
      const { data } = await orgApi.onboard({
        ...payload,
        owner_first_name: owner.first_name.trim(),
        owner_last_name: owner.last_name.trim(),
        owner_phone: toE164(ownerPhone),
        owner_email: owner.email.trim(),
        country_code: ownerPhone.country_code,
      })
      return data
    },
    onSuccess: (result) => {
      if (!result) {
        toast.success('Organization updated')
      } else if (result.sms_sent) {
        toast.success(`${result.organization.name} created. We texted ${result.owner.full_name} how to log in.`)
      } else {
        toast.warning(
          `${result.organization.name} created, but we couldn't text the owner. Ask them to set a password on the Forgot Password page, using ${result.owner.phone}.`,
          { duration: 10000 },
        )
      }
      setEditing(null)
      setCreating(false)
      void qc.invalidateQueries({ queryKey: ['admin-orgs'] })
      void qc.invalidateQueries({ queryKey: ['admin-orgs-preview'] })
      void qc.invalidateQueries({ queryKey: ['admin-orgs-filter'] })
      void qc.invalidateQueries({ queryKey: ['admin-dashboard'] })
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const orgAction = useMutation({
    mutationFn: async ({
      id,
      type,
    }: {
      id: string
      type: 'activate' | 'deactivate' | 'delete'
    }) => {
      if (type === 'activate') return orgApi.activate(id)
      if (type === 'deactivate') return orgApi.deactivate(id)
      return orgApi.remove(id)
    },
    onSuccess: (_data, vars) => {
      const labels = {
        activate: 'Organization activated',
        deactivate: 'Organization taken off the grid',
        delete: 'Organization deleted',
      }
      toast.success(labels[vars.type])
      void qc.invalidateQueries({ queryKey: ['admin-orgs'] })
      void qc.invalidateQueries({ queryKey: ['admin-orgs-preview'] })
      void qc.invalidateQueries({ queryKey: ['admin-orgs-filter'] })
      void qc.invalidateQueries({ queryKey: ['admin-dashboard'] })
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const orgs = (query.data || []).filter((o) => (showInactive ? true : o.is_active !== false))

  return (
    <div className="mx-auto max-w-7xl space-y-4">
      <PageHeader
        title="Organizations"
        subtitle="Add, update, deactivate, or delete partner organizations"
        actions={<Button onClick={openCreate}>Add organization</Button>}
      />
      <div className="admin-card p-4 sm:p-5">
        <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center">
          <div className="min-w-0 flex-1">
            <SearchInput value={search} onChange={setSearch} placeholder="Search organizations…" />
          </div>
          <label className="inline-flex items-center gap-2 text-sm text-slate-600">
            <input
              type="checkbox"
              checked={showInactive}
              onChange={(e) => setShowInactive(e.target.checked)}
              className="rounded border-slate-300"
            />
            Show inactive
          </label>
        </div>
        {query.isLoading && !query.data ? (
          <LoadingState />
        ) : query.isError ? (
          <ErrorState message={getErrorMessage(query.error)} onRetry={() => query.refetch()} />
        ) : !orgs.length ? (
          <p className="rounded-2xl border border-dashed border-[var(--color-border)] py-12 text-center text-sm text-slate-500">
            No organizations yet. Add one to get started.
          </p>
        ) : (
          <div className="overflow-x-auto rounded-2xl border border-[var(--color-border)]">
            <table className="min-w-[720px] w-full text-left text-sm">
              <thead className="bg-slate-50/80 text-slate-500">
                <tr>
                  <th className="px-5 py-3.5 font-medium">Name</th>
                  <th className="px-5 py-3.5 font-medium">Contact</th>
                  <th className="px-5 py-3.5 font-medium">Members</th>
                  <th className="px-5 py-3.5 font-medium">Staff</th>
                  <th className="px-5 py-3.5 font-medium">Status</th>
                  <th className="px-5 py-3.5 font-medium">Created</th>
                  <th className="px-5 py-3.5 font-medium">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-black/[0.04] bg-white">
                {orgs.map((o) => (
                  <tr
                    key={o.id}
                    className="cursor-pointer align-top hover:bg-slate-50/70"
                    onClick={() => navigate(`/admin/organizations/${o.id}`)}
                  >
                    <td className="px-5 py-3.5">
                      <Link
                        to={`/admin/organizations/${o.id}`}
                        className="font-medium text-[var(--color-charcoal)] hover:text-[var(--color-blue)] hover:underline"
                        onClick={(e) => e.stopPropagation()}
                      >
                        {o.name}
                      </Link>
                      {o.description ? (
                        <p className="mt-0.5 line-clamp-2 text-xs text-slate-400">{o.description}</p>
                      ) : null}
                    </td>
                    <td className="px-5 py-3.5 text-slate-600">
                      <p>{o.phone || '—'}</p>
                      <p className="text-xs text-slate-400">{o.email || ''}</p>
                    </td>
                    <td className="px-5 py-3.5">{o.people_count}</td>
                    <td className="px-5 py-3.5">{o.member_count}</td>
                    <td className="px-5 py-3.5">
                      <StatusBadge status={o.is_active === false ? 'blocked' : 'active'} />
                    </td>
                    <td className="px-5 py-3.5 text-slate-500">
                      {new Date(o.created_at).toLocaleDateString()}
                    </td>
                    <td className="px-5 py-3.5" onClick={(e) => e.stopPropagation()}>
                      <div className="flex flex-wrap gap-1.5">
                        <Button
                          variant="secondary"
                          className="px-2.5 py-1.5 text-xs"
                          onClick={() => openEdit(o)}
                        >
                          Edit
                        </Button>
                        {o.is_active === false ? (
                          <Button
                            variant="secondary"
                            className="px-2.5 py-1.5 text-xs"
                            disabled={orgAction.isPending}
                            onClick={() => orgAction.mutate({ id: o.id, type: 'activate' })}
                          >
                            Activate
                          </Button>
                        ) : (
                          <Button
                            variant="secondary"
                            className="px-2.5 py-1.5 text-xs"
                            disabled={orgAction.isPending}
                            onClick={() => {
                              if (
                                window.confirm(
                                  `Take ${o.name} off the grid? It will be marked inactive.`,
                                )
                              ) {
                                orgAction.mutate({ id: o.id, type: 'deactivate' })
                              }
                            }}
                          >
                            Deactivate
                          </Button>
                        )}
                        <Button
                          variant="danger"
                          className="px-2.5 py-1.5 text-xs"
                          disabled={orgAction.isPending}
                          onClick={() => {
                            if (
                              window.confirm(
                                `Permanently delete ${o.name}? This cannot be undone.`,
                              )
                            ) {
                              orgAction.mutate({ id: o.id, type: 'delete' })
                            }
                          }}
                        >
                          Delete
                        </Button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <Modal
        open={creating || Boolean(editing)}
        title={editing ? 'Edit organization' : 'Add organization'}
        onClose={() => {
          setCreating(false)
          setEditing(null)
        }}
      >
        <div className="space-y-3">
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Name</span>
            <Input
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              placeholder="Organization name"
            />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Organization phone (optional)</span>
            <Input
              value={form.phone}
              onChange={(e) => setForm({ ...form, phone: e.target.value })}
            />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Organization email (optional)</span>
            <Input
              value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
              placeholder="ops@school.org"
            />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Address</span>
            <Input
              value={form.address}
              onChange={(e) => setForm({ ...form, address: e.target.value })}
            />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Description</span>
            <Input
              value={form.description}
              onChange={(e) => setForm({ ...form, description: e.target.value })}
            />
          </label>
          {!editing ? (
            <div className="space-y-3 rounded-2xl bg-slate-50/80 p-3">
              <div>
                <p className="text-sm font-semibold text-[var(--color-charcoal)]">Owner</p>
                <p className="text-xs text-slate-500">
                  Their representative owns this organization. We text them how to log in.
                </p>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <Input
                  placeholder="First name"
                  aria-label="Owner first name"
                  value={owner.first_name}
                  onChange={(e) => setOwner({ ...owner, first_name: e.target.value })}
                />
                <Input
                  placeholder="Last name"
                  aria-label="Owner last name"
                  value={owner.last_name}
                  onChange={(e) => setOwner({ ...owner, last_name: e.target.value })}
                />
              </div>
              <PhoneInput value={ownerPhone} onChange={setOwnerPhone} />
              <Input
                type="email"
                placeholder="Email (optional)"
                aria-label="Owner email (optional)"
                value={owner.email}
                onChange={(e) => setOwner({ ...owner, email: e.target.value })}
              />
              {ownerError ? <p className="text-sm text-[var(--color-red)]">{ownerError}</p> : null}
            </div>
          ) : null}
          <Button
            className="w-full"
            disabled={!form.name.trim() || saveOrg.isPending}
            onClick={() => {
              if (!editing) {
                if (!owner.first_name.trim()) return setOwnerError("Enter the owner's first name.")
                if (!isValidNationalPhone(ownerPhone.national)) {
                  return setOwnerError("Enter the owner's phone number.")
                }
                if (!isValidEmail(owner.email)) {
                  return setOwnerError('Enter a valid email, or leave it empty.')
                }
              }
              setOwnerError('')
              saveOrg.mutate()
            }}
          >
            {saveOrg.isPending ? 'Saving…' : editing ? 'Save changes' : 'Create organization'}
          </Button>
        </div>
      </Modal>
    </div>
  )
}

export function AdminUsers() {
  const qc = useQueryClient()
  const [search, setSearch] = useState('')
  const debouncedSearch = useDebouncedValue(search)
  const [source, setSource] = useState('')
  const [status, setStatus] = useState('')
  const [organization, setOrganization] = useState('')
  const [page, setPage] = useState(1)
  const { user: me } = useAuth()
  const isAdmin = Boolean(me?.is_platform_admin)
  const [adding, setAdding] = useState(false)
  const [justAddedId, setJustAddedId] = useState<string | null>(null)

  useEffect(() => {
    setPage(1)
  }, [debouncedSearch, source, status, organization])

  const orgsQuery = useQuery({
    queryKey: ['admin-orgs-filter'],
    queryFn: async () => unwrapList((await orgApi.list({ page_size: '200' })).data),
  })

  const params: Record<string, string> = {
    search: debouncedSearch,
    ordering: '-created_at',
    page_size: String(PAGE_SIZE),
    page: String(page),
  }
  if (source) params.source = source
  if (status) params.status = status
  if (organization) params.organization = organization

  const query = useQuery({
    queryKey: ['admin-users', params],
    queryFn: async () => {
      const { data } = await usersApi.list(params)
      if (Array.isArray(data)) {
        return { count: data.length, results: data, next: null, previous: null }
      }
      return data
    },
    placeholderData: keepPreviousData,
    refetchInterval: 30000,
  })

  const runAction = useMutation({
    mutationFn: async ({
      id,
      action,
    }: {
      id: string
      action: 'mute' | 'unmute' | 'block' | 'unblock' | 'delete'
    }) => {
      if (action === 'delete') return usersApi.remove(id)
      return usersApi[action](id)
    },
    onSuccess: (_data, vars) => {
      const labels = {
        mute: 'User muted',
        unmute: 'User unmuted',
        block: 'User blocked',
        unblock: 'User unblocked',
        delete: 'User deleted',
      }
      toast.success(labels[vars.action])
      void qc.invalidateQueries({ queryKey: ['admin-users'] })
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const users = query.data?.results || []
  const totalCount = query.data?.count ?? users.length
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE))
  const activeCount = users.filter((u) => u.is_active !== false && !u.is_muted).length
  const mutedCount = users.filter((u) => u.is_muted && u.is_active !== false).length
  const blockedCount = users.filter((u) => u.is_active === false).length
  const watchCount = users.filter((u) => u.has_watch).length

  return (
    <div className="mx-auto max-w-7xl space-y-4">
      <PageHeader
        title="User management"
        subtitle={
          isAdmin
            ? 'All platform accounts — mobile app and bracelet wearers'
            : 'The people you have registered'
        }
        actions={<Button onClick={() => setAdding(true)}>Add user</Button>}
      />

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { label: 'Total', value: totalCount },
          { label: 'Active (page)', value: activeCount },
          { label: 'Muted (page)', value: mutedCount },
          { label: 'With watch (page)', value: watchCount },
        ].map((item) => (
          <div key={item.label} className="admin-card px-4 py-3">
            <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-slate-400">
              {item.label}
            </p>
            <p className="mt-1 font-display text-2xl text-[var(--color-charcoal)]">{item.value}</p>
          </div>
        ))}
      </div>

      <div className="admin-card p-4 sm:p-5">
        <div className="mb-4 flex flex-col gap-3 lg:flex-row lg:items-center">
          <div className="min-w-0 flex-1">
            <SearchInput
              value={search}
              onChange={setSearch}
              placeholder="Search name, username, phone, bracelet ID…"
            />
          </div>
          <Select
            className="lg:max-w-[10rem]"
            value={source}
            onChange={(e) => setSource(e.target.value)}
          >
            <option value="">All sources</option>
            <option value="app">App</option>
            <option value="watch">Watch</option>
            <option value="org">Organization</option>
            <option value="independent">Independent</option>
          </Select>
          <Select
            className="lg:max-w-[10rem]"
            value={status}
            onChange={(e) => setStatus(e.target.value)}
          >
            <option value="">All statuses</option>
            <option value="active">Active</option>
            <option value="muted">Muted</option>
            <option value="blocked">Blocked</option>
          </Select>
          <Select
            className="lg:max-w-[14rem]"
            value={organization}
            onChange={(e) => setOrganization(e.target.value)}
          >
            <option value="">All organizations</option>
            {orgsQuery.data?.map((o) => (
              <option key={o.id} value={o.id}>
                {o.name}
              </option>
            ))}
          </Select>
        </div>

        {query.isLoading && !query.data ? (
          <LoadingState />
        ) : query.isError ? (
          <ErrorState message={getErrorMessage(query.error)} onRetry={() => query.refetch()} />
        ) : !users.length ? (
          <p className="rounded-2xl border border-dashed border-[var(--color-border)] py-12 text-center text-sm text-slate-500">
            No users match these filters.
          </p>
        ) : (
          <>
            <div className="overflow-x-auto rounded-2xl border border-[var(--color-border)]">
              <table className="min-w-[980px] w-full text-left text-sm">
                <thead className="bg-slate-50/80 text-slate-500">
                  <tr>
                    <th className="px-4 py-3.5 font-medium">User</th>
                    <th className="px-4 py-3.5 font-medium">Phone</th>
                    <th className="px-4 py-3.5 font-medium">Type</th>
                    <th className="px-4 py-3.5 font-medium">Sources</th>
                    <th className="px-4 py-3.5 font-medium">Bracelet</th>
                    <th className="px-4 py-3.5 font-medium">Status</th>
                    <th className="px-4 py-3.5 font-medium">Joined</th>
                    <th className="sticky right-0 bg-slate-50 px-4 py-3.5 font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-black/[0.04] bg-white">
                  {users.map((u) => {
                    const statusLabel =
                      u.status_label ||
                      (u.is_active === false ? 'blocked' : u.is_muted ? 'muted' : 'active')
                    return (
                      <tr
                        key={u.id}
                        className={`align-top hover:bg-slate-50/70 ${u.id === justAddedId ? 'bg-blue-50' : ''}`}
                      >
                        <td className="px-4 py-3.5">
                          <div className="flex items-start gap-2.5">
                            <Avatar name={u.full_name} photoUrl={u.photo_url} size="sm" />
                            <div className="min-w-0">
                              <Link
                                to={`/admin/users/${u.id}`}
                                className="font-medium text-[var(--color-charcoal)] hover:text-[var(--color-blue)] hover:underline"
                              >
                                {u.full_name}
                              </Link>
                              <p className="font-mono text-xs text-slate-500">{u.username}</p>
                              {u.organization_name ? (
                                <p className="text-xs text-slate-500">{u.organization_name}</p>
                              ) : null}
                              {u.email ? <p className="text-xs text-slate-500">{u.email}</p> : null}
                              {u.platform_role === 'registrar' ? (
                                <p className="mt-1 text-[11px] font-semibold uppercase tracking-wide text-[var(--color-blue)]">
                                  Registrar
                                </p>
                              ) : null}
                          {u.is_platform_admin ? (
                            <p className="mt-1 text-[11px] font-semibold uppercase tracking-wide text-[var(--color-blue)]">
                              Platform admin
                            </p>
                          ) : null}
                            </div>
                          </div>
                        </td>
                        <td className="px-4 py-3.5 whitespace-nowrap">{u.phone || '—'}</td>
                        <td className="px-4 py-3.5 capitalize">{u.account_type}</td>
                        <td className="px-4 py-3.5">
                          <div className="flex flex-wrap gap-1">
                            {(u.sources || ['app']).map((src: string) => (
                              <span
                                key={src}
                                className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-medium uppercase tracking-wide text-slate-600"
                              >
                                {src}
                              </span>
                            ))}
                          </div>
                        </td>
                        <td className="px-4 py-3.5">
                          {u.device_id ? (
                            <span className="font-mono text-xs">{u.device_id}</span>
                          ) : u.is_platform_admin ||
                            u.platform_role === 'registrar' ||
                            u.account_type === 'organization' ? (
                            '—'
                          ) : (
                            <span className="text-xs font-medium text-amber-600">No bracelet</span>
                          )}
                        </td>
                        <td className="px-4 py-3.5">
                          <StatusBadge status={statusLabel} />
                          {!u.phone_verified && !u.email_verified ? (
                            <p className="mt-1 text-[11px] text-amber-600">Not verified</p>
                          ) : null}
                        </td>
                        <td className="px-4 py-3.5 whitespace-nowrap text-slate-500">
                          {new Date(u.created_at).toLocaleDateString()}
                        </td>
                        <td className="sticky right-0 bg-white px-4 py-3.5">
                          <div className="flex flex-wrap gap-1.5">
                            <Link
                              to={`/admin/users/${u.id}`}
                              className="inline-flex items-center rounded-xl border border-[var(--color-border)] bg-white px-2.5 py-1.5 text-xs font-semibold text-[var(--color-charcoal)] hover:bg-slate-50"
                            >
                              Manage
                            </Link>
                            {!isAdmin ? null : u.is_muted ? (
                              <Button
                                variant="secondary"
                                className="px-2.5 py-1.5 text-xs"
                                disabled={runAction.isPending}
                                onClick={() => runAction.mutate({ id: u.id, action: 'unmute' })}
                              >
                                Unmute
                              </Button>
                            ) : (
                              <Button
                                variant="secondary"
                                className="px-2.5 py-1.5 text-xs"
                                disabled={runAction.isPending}
                                onClick={() => runAction.mutate({ id: u.id, action: 'mute' })}
                              >
                                Mute
                              </Button>
                            )}
                            {!isAdmin ? null : u.is_active === false ? (
                              <Button
                                variant="secondary"
                                className="px-2.5 py-1.5 text-xs"
                                disabled={runAction.isPending}
                                onClick={() => runAction.mutate({ id: u.id, action: 'unblock' })}
                              >
                                Unblock
                              </Button>
                            ) : (
                              <Button
                                variant="secondary"
                                className="px-2.5 py-1.5 text-xs"
                                disabled={runAction.isPending || u.is_platform_admin}
                                onClick={() => {
                                  if (
                                    window.confirm(
                                      `Block ${u.full_name}? They will not be able to sign in.`,
                                    )
                                  ) {
                                    runAction.mutate({ id: u.id, action: 'block' })
                                  }
                                }}
                              >
                                Block
                              </Button>
                            )}
                            {isAdmin ? (
                              <Button
                                variant="danger"
                                className="px-2.5 py-1.5 text-xs"
                                disabled={runAction.isPending || u.is_platform_admin}
                                onClick={() => {
                                  if (
                                    window.confirm(
                                      `Permanently delete ${u.full_name}? This cannot be undone.`,
                                    )
                                  ) {
                                    runAction.mutate({ id: u.id, action: 'delete' })
                                  }
                                }}
                              >
                                Delete
                              </Button>
                            ) : null}
                          </div>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
            <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
              <p className="text-xs text-slate-400">
                Page {page} of {totalPages} · {totalCount} users
                {blockedCount > 0 ? ` · ${blockedCount} blocked on this page` : ''}
              </p>
              <div className="flex gap-2">
                <Button
                  variant="secondary"
                  className="px-3 py-1.5 text-xs"
                  disabled={page <= 1 || query.isFetching}
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                >
                  Previous
                </Button>
                <Button
                  variant="secondary"
                  className="px-3 py-1.5 text-xs"
                  disabled={page >= totalPages || query.isFetching}
                  onClick={() => setPage((p) => p + 1)}
                >
                  Next
                </Button>
              </div>
            </div>
          </>
        )}
      </div>

      <AddUserModal
        open={adding}
        title="Add user"
        onClose={() => setAdding(false)}
        onCreated={(created) => {
          setSearch('')
          setSource('')
          setStatus('')
          setOrganization('')
          setPage(1)
          setJustAddedId(created.id)
        }}
      />
    </div>
  )
}

export function AdminAudit() {
  const [search, setSearch] = useState('')
  const debouncedSearch = useDebouncedValue(search)
  const query = useQuery({
    queryKey: ['audit', debouncedSearch],
    queryFn: async () => unwrapList((await auditApi.list({ search: debouncedSearch })).data),
    placeholderData: keepPreviousData,
  })
  return (
    <div className="mx-auto max-w-7xl space-y-4">
      <PageHeader title="Audit logs" subtitle="Immutable activity history" />
      <div className="admin-card p-4 sm:p-5">
        <div className="mb-4">
          <SearchInput value={search} onChange={setSearch} />
        </div>
        {query.isLoading && !query.data ? (
          <LoadingState />
        ) : (
          <div className="overflow-x-auto rounded-2xl border border-[var(--color-border)]">
            <table className="min-w-[640px] w-full text-left text-sm">
              <thead className="bg-slate-50/80 text-slate-500">
                <tr>
                  <th className="px-5 py-3.5 font-medium">Time</th>
                  <th className="px-5 py-3.5 font-medium">Actor</th>
                  <th className="px-5 py-3.5 font-medium">Action</th>
                  <th className="px-5 py-3.5 font-medium">Object</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-black/[0.04] bg-white">
                {query.data?.map((a) => (
                  <tr key={a.id} className="hover:bg-slate-50/70">
                    <td className="whitespace-nowrap px-5 py-3.5 text-slate-500">
                      {new Date(a.created_at).toLocaleString()}
                    </td>
                    <td className="px-5 py-3.5">{a.actor_email || 'System'}</td>
                    <td className="px-5 py-3.5 font-medium">{a.action}</td>
                    <td className="px-5 py-3.5">
                      {a.object_type} {a.object_id?.slice(0, 8)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}

export function AdminSms() {
  const [search, setSearch] = useState('')
  const debouncedSearch = useDebouncedValue(search)
  const [direction, setDirection] = useState('')
  const [status, setStatus] = useState('')
  const [source, setSource] = useState('')
  const [provider, setProvider] = useState('')

  const params: Record<string, string> = {
    search: debouncedSearch,
    ordering: '-created_at',
    page_size: '100',
  }
  if (direction) params.direction = direction
  if (status) params.status = status
  if (provider) params.provider = provider

  const stats = useQuery({
    queryKey: ['admin-sms-stats', direction, status, provider, debouncedSearch],
    queryFn: async () => (await smsApi.stats(params)).data,
    refetchInterval: 15000,
  })
  const query = useQuery({
    queryKey: ['admin-sms', params],
    queryFn: async () => unwrapList((await smsApi.list(params)).data),
    placeholderData: keepPreviousData,
    refetchInterval: 15000,
  })

  const currency = stats.data?.currency || 'UGX'
  const formatSpend = (n?: number) =>
    `${currency} ${Number(n || 0).toLocaleString(undefined, { maximumFractionDigits: 2 })}`

  const sourceOf = (row: { source?: string; origin?: string }) => {
    if (row.source) return row.source
    const map: Record<string, string> = {
      app: 'App',
      alerts: 'Blaces',
      api: 'Blaces',
      webhook: 'Webhook',
      other: 'Other',
    }
    return map[row.origin || 'other'] || 'Other'
  }

  const rows = (query.data || []).filter((row) =>
    source ? sourceOf(row) === source : true,
  )

  return (
    <div className="mx-auto max-w-7xl space-y-4">
      <PageHeader
        title="SMS messages"
        subtitle="Message log and spend across KaCyber / Africa's Talking"
      />

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { label: 'Total', value: stats.data?.total ?? query.data?.length ?? 0 },
          { label: 'Spent', value: formatSpend(stats.data?.total_spent) },
          { label: 'Sent', value: stats.data?.sent ?? '—' },
          { label: 'Failed', value: stats.data?.failed ?? '—' },
        ].map((item) => (
          <div key={item.label} className="admin-card px-4 py-3">
            <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-slate-400">
              {item.label}
            </p>
            <p className="mt-1 font-display text-2xl text-[var(--color-charcoal)]">{item.value}</p>
          </div>
        ))}
      </div>

      <div className="admin-card p-4 sm:p-5">
        <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center">
          <div className="min-w-0 flex-1">
            <SearchInput value={search} onChange={setSearch} placeholder="Search phone, message, id…" />
          </div>
          <Select value={direction} onChange={(e) => setDirection(e.target.value)}>
            <option value="">All directions</option>
            <option value="outbound">Outbound</option>
            <option value="inbound">Inbound</option>
          </Select>
          <Select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">All statuses</option>
            <option value="sent">Sent</option>
            <option value="failed">Failed</option>
            <option value="queued">Queued</option>
          </Select>
          <Select value={source} onChange={(e) => setSource(e.target.value)}>
            <option value="">All sources</option>
            <option value="App">App</option>
            <option value="Blaces">Blaces</option>
            <option value="Webhook">Webhook</option>
            <option value="Other">Other</option>
          </Select>
          <Select value={provider} onChange={(e) => setProvider(e.target.value)}>
            <option value="">All providers</option>
            <option value="kacyber">KaCyber</option>
            <option value="africastalking">Africa&apos;s Talking</option>
          </Select>
        </div>

        {query.isLoading && !query.data ? (
          <LoadingState />
        ) : query.isError ? (
          <ErrorState message={getErrorMessage(query.error)} onRetry={() => query.refetch()} />
        ) : !rows.length ? (
          <p className="rounded-2xl border border-dashed border-[var(--color-border)] py-12 text-center text-sm text-slate-500">
            No SMS messages match these filters.
          </p>
        ) : (
          <div className="overflow-x-auto rounded-2xl border border-[var(--color-border)]">
            <table className="min-w-[960px] w-full text-left text-sm">
              <thead className="bg-slate-50/80 text-slate-500">
                <tr>
                  <th className="px-4 py-3.5 font-medium">Time</th>
                  <th className="px-4 py-3.5 font-medium">Source</th>
                  <th className="px-4 py-3.5 font-medium">Direction</th>
                  <th className="px-4 py-3.5 font-medium">Phone</th>
                  <th className="px-4 py-3.5 font-medium">Purpose</th>
                  <th className="px-4 py-3.5 font-medium">Provider</th>
                  <th className="px-4 py-3.5 font-medium">Status</th>
                  <th className="px-4 py-3.5 font-medium">Cost</th>
                  <th className="px-4 py-3.5 font-medium">Message</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-black/[0.04] bg-white">
                {rows.map((row) => (
                  <tr key={row.id} className="align-top hover:bg-slate-50/70">
                    <td className="whitespace-nowrap px-4 py-3.5 text-slate-500">
                      {new Date(row.created_at).toLocaleString()}
                    </td>
                    <td className="px-4 py-3.5">
                      <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-medium uppercase tracking-wide text-slate-600">
                        {sourceOf(row)}
                      </span>
                    </td>
                    <td className="px-4 py-3.5 capitalize">{row.direction}</td>
                    <td className="px-4 py-3.5 font-medium text-[var(--color-charcoal)]">
                      {row.phone_number}
                      {row.user_email ? (
                        <p className="mt-0.5 text-xs font-normal text-slate-400">{row.user_email}</p>
                      ) : null}
                    </td>
                    <td className="px-4 py-3.5">{row.purpose || '—'}</td>
                    <td className="px-4 py-3.5">{row.provider || '—'}</td>
                    <td className="px-4 py-3.5">
                      <StatusBadge status={row.status} />
                      {row.error ? (
                        <p className="mt-1 max-w-[12rem] text-xs text-[var(--color-red)]">{row.error}</p>
                      ) : null}
                    </td>
                    <td className="px-4 py-3.5 whitespace-nowrap">{row.cost || '—'}</td>
                    <td className="px-4 py-3.5 max-w-xs">
                      <p className="line-clamp-3 text-slate-700">{row.message}</p>
                      {row.provider_message_id ? (
                        <p className="mt-1 truncate text-xs text-slate-400">{row.provider_message_id}</p>
                      ) : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}

export function AdminSettings() {
  const { user: me } = useAuth()
  const isAdmin = Boolean(me?.is_platform_admin)
  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [showDev, setShowDev] = useState(false)

  const changePassword = useMutation({
    mutationFn: () => authApi.changePassword(currentPassword, newPassword),
    onSuccess: () => {
      toast.success('Password updated')
      setCurrentPassword('')
      setNewPassword('')
      setConfirm('')
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const submit = () => {
    if (newPassword.length < 8) {
      toast.error('New password must be at least 8 characters')
      return
    }
    if (newPassword !== confirm) {
      toast.error('New passwords do not match')
      return
    }
    changePassword.mutate()
  }

  return (
    <div className="mx-auto max-w-7xl space-y-4">
      <PageHeader title="Account settings" subtitle="Manage your account" />

      <div className="admin-card space-y-4 p-5 sm:p-6">
        <h2 className="text-base font-semibold text-[var(--color-charcoal)]">My profile</h2>
        <ProfileEditor />
      </div>

      {isAdmin ? <StaffSection /> : null}

      <div className="admin-card space-y-4 p-5 sm:p-6">
        <div>
          <h2 className="text-base font-semibold text-[var(--color-charcoal)]">Change password</h2>
          <p className="mt-1 text-sm text-slate-500">
            Update the password for the account you are signed in with.
          </p>
        </div>
        <label className="block space-y-1.5">
          <span className="text-sm font-medium">Current password</span>
          <PasswordInput
            value={currentPassword}
            onChange={(e) => setCurrentPassword(e.target.value)}
            autoComplete="current-password"
          />
        </label>
        <label className="block space-y-1.5">
          <span className="text-sm font-medium">New password</span>
          <PasswordInput
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
            autoComplete="new-password"
          />
        </label>
        <label className="block space-y-1.5">
          <span className="text-sm font-medium">Confirm new password</span>
          <PasswordInput
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            autoComplete="new-password"
          />
        </label>
        <Button
          disabled={
            !currentPassword || !newPassword || !confirm || changePassword.isPending
          }
          onClick={submit}
        >
          {changePassword.isPending ? 'Updating…' : 'Update password'}
        </Button>
      </div>

      <div className={isAdmin ? 'admin-card p-5 sm:p-6' : 'hidden'}>
        <button
          type="button"
          className="flex w-full items-center justify-between text-left text-sm font-semibold text-[var(--color-charcoal)]"
          onClick={() => setShowDev((v) => !v)}
        >
          Developer / webhook notes
          <span className="text-slate-400">{showDev ? 'Hide' : 'Show'}</span>
        </button>
        {showDev ? (
          <div className="mt-4 space-y-2 text-sm text-slate-600">
            <p>
              SMS format:{' '}
              <code className="rounded-lg bg-slate-100 px-2 py-0.5">
                SB|device_id|alert_code|lat|lng
              </code>
            </p>
            <p>
              Webhook:{' '}
              <code className="rounded-lg bg-slate-100 px-2 py-0.5">
                POST /api/webhooks/africastalking/sms/
              </code>
            </p>
            <p>
              Override parser with{' '}
              <code className="rounded-lg bg-slate-100 px-2 py-0.5">BRACELET_SMS_REGEX</code> env
              var.
            </p>
            <p>
              Protect webhook with{' '}
              <code className="rounded-lg bg-slate-100 px-2 py-0.5">WEBHOOK_SHARED_SECRET</code> /
              header{' '}
              <code className="rounded-lg bg-slate-100 px-2 py-0.5">X-Webhook-Secret</code>.
            </p>
          </div>
        ) : null}
      </div>
    </div>
  )
}

export function AdminAlerts() {
  return <AlertsPage scoped={false} />
}
export function AdminIncidents() {
  return <IncidentsPage scoped={false} />
}
export function AdminReports() {
  return <ReportsPage scoped={false} />
}
