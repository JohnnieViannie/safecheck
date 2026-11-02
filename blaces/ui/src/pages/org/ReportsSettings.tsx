import { useQuery } from '@tanstack/react-query'
import {
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { getErrorMessage, useAuth } from '../../api/auth'
import { orgApi, reportApi } from '../../api/services'
import { StaffInviteForm } from '../../components/StaffInviteForm'
import { ErrorState, Input, LoadingState, PageHeader, StatCard } from '../../components/ui'
import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { Button, Textarea } from '../../components/ui'

export function ReportsPage({ scoped = true }: { scoped?: boolean }) {
  const { activeOrgId } = useAuth()
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const params: Record<string, string> = {}
  if (scoped && activeOrgId) params.organization = activeOrgId
  if (from) params.from = from
  if (to) params.to = to

  const query = useQuery({
    queryKey: ['reports', params],
    queryFn: async () => (await reportApi.summary(params)).data,
  })

  if (query.isLoading) return <LoadingState />
  if (query.isError) return <ErrorState message={getErrorMessage(query.error)} onRetry={() => query.refetch()} />
  const r = query.data!

  return (
    <div>
      <PageHeader title="Reports" subtitle="Alerts, incidents, and device utilization" />
      <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
        <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="w-full sm:max-w-[180px]" />
        <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="w-full sm:max-w-[180px]" />
      </div>
      <div className="grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-4">
        <StatCard label="Alerts" value={r.totals.alerts} />
        <StatCard label="Incidents" value={r.totals.incidents} />
        <StatCard label="Resolution rate" value={`${r.totals.resolution_rate}%`} tone="ok" />
        <StatCard
          label="Avg ack time"
          value={r.totals.avg_ack_seconds != null ? `${Math.round(r.totals.avg_ack_seconds)}s` : '—'}
        />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        <div className="console-card p-4">
          <h3 className="mb-3 font-semibold">Alerts by date</h3>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={r.alerts_by_date}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                <YAxis allowDecimals={false} />
                <Tooltip />
                <Line type="monotone" dataKey="count" stroke="#0B5FA5" strokeWidth={2} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>
        <div className="console-card p-4">
          <h3 className="mb-3 font-semibold">Incidents by date</h3>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={r.incidents_by_date}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                <YAxis allowDecimals={false} />
                <Tooltip />
                <Bar dataKey="count" fill="#C41E26" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        <div className="rounded-lg border border-[var(--color-border)] bg-white p-4">
          <h3 className="mb-3 font-semibold">Alerts by person</h3>
          <ul className="space-y-2 text-sm">
            {r.alerts_by_person.map((x) => (
              <li key={x.person_id} className="flex justify-between">
                <span>{x.name}</span>
                <span className="font-medium">{x.count}</span>
              </li>
            ))}
            {!r.alerts_by_person.length ? <li className="text-slate-500">No data</li> : null}
          </ul>
        </div>
        <div className="rounded-lg border border-[var(--color-border)] bg-white p-4">
          <h3 className="mb-3 font-semibold">Device utilization</h3>
          <dl className="grid grid-cols-3 gap-3 text-center text-sm">
            <div>
              <dt className="text-slate-500">Total</dt>
              <dd className="text-2xl font-semibold">{r.device_utilization.total}</dd>
            </div>
            <div>
              <dt className="text-slate-500">In use</dt>
              <dd className="text-2xl font-semibold">{r.device_utilization.in_use}</dd>
            </div>
            <div>
              <dt className="text-slate-500">Inactive</dt>
              <dd className="text-2xl font-semibold">{r.device_utilization.inactive}</dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
  )
}

export function OrgSettingsPage() {
  const { activeOrgId } = useAuth()
  const qc = useQueryClient()
  const org = useQuery({
    queryKey: ['org', activeOrgId],
    queryFn: async () => (await orgApi.get(activeOrgId!)).data,
    enabled: !!activeOrgId,
  })
  const members = useQuery({
    queryKey: ['org-members', activeOrgId],
    queryFn: async () => (await orgApi.members(activeOrgId!)).data,
    enabled: !!activeOrgId,
  })
  const invitations = useQuery({
    queryKey: ['org-invites', activeOrgId],
    queryFn: async () => (await orgApi.invitations(activeOrgId!)).data,
    enabled: !!activeOrgId,
  })

  const [form, setForm] = useState({ name: '', description: '', email: '', phone: '' })
  const loaded = org.data
  if (loaded && form.name === '' && loaded.name) {
    // sync once
  }

  const save = useMutation({
    mutationFn: () =>
      orgApi.update(activeOrgId!, {
        name: form.name || loaded?.name,
        description: form.description || loaded?.description,
        email: form.email || loaded?.email,
        phone: form.phone || loaded?.phone,
      }),
    onSuccess: () => {
      toast.success('Organization updated')
      void qc.invalidateQueries({ queryKey: ['org', activeOrgId] })
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  if (!activeOrgId) return <ErrorState message="Select an organization" />
  if (org.isLoading) return <LoadingState />

  const o = org.data!

  return (
    <div>
      <PageHeader title="Organization settings" subtitle={o.name} />
      <div className="grid gap-6 lg:grid-cols-2">
        <div className="space-y-3 rounded-lg border border-[var(--color-border)] bg-white p-4">
          <h3 className="font-semibold">Profile</h3>
          <Input defaultValue={o.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
          <Textarea
            defaultValue={o.description}
            onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))}
          />
          <Input defaultValue={o.email} placeholder="Email" onChange={(e) => setForm((f) => ({ ...f, email: e.target.value }))} />
          <Input defaultValue={o.phone} placeholder="Phone" onChange={(e) => setForm((f) => ({ ...f, phone: e.target.value }))} />
          <Button onClick={() => save.mutate()}>Save</Button>
        </div>
        <div className="space-y-3 rounded-lg border border-[var(--color-border)] bg-white p-4">
          <h3 className="font-semibold">Invite staff</h3>
          <StaffInviteForm organizationId={activeOrgId} />
          <h4 className="pt-4 font-medium">Pending invitations</h4>
          <ul className="space-y-1 text-sm">
            {(Array.isArray(invitations.data) ? invitations.data : []).map((inv) => (
              <li key={inv.id} className="flex justify-between">
                <span>{inv.phone || inv.email}</span>
                <span className="text-slate-500">
                  {inv.role} {inv.is_valid ? '' : '(invalid)'}
                </span>
              </li>
            ))}
          </ul>
        </div>
      </div>
      <div className="mt-6 rounded-lg border border-[var(--color-border)] bg-white p-4">
        <h3 className="font-semibold">Staff</h3>
        <ul className="mt-3 divide-y divide-[var(--color-border)] text-sm">
          {(Array.isArray(members.data) ? members.data : []).map(
            (m) => (
              <li key={m.id} className="flex justify-between py-2">
                <span>
                  {m.user_name} <span className="text-slate-500">({m.user_phone || m.user_email})</span>
                </span>
                <span className="font-medium">{m.role}</span>
              </li>
            ),
          )}
        </ul>
      </div>
    </div>
  )
}

export function RespondersPage() {
  const { activeOrgId } = useAuth()
  const members = useQuery({
    queryKey: ['responders', activeOrgId],
    queryFn: async () => (await orgApi.members(activeOrgId!)).data,
    enabled: !!activeOrgId,
  })
  if (!activeOrgId) return <ErrorState message="Select an organization" />
  if (members.isLoading) return <LoadingState />
  const list = (Array.isArray(members.data) ? members.data : []).filter((m: { role: string }) =>
    ['OWNER', 'ADMIN', 'STAFF', 'RESPONDER'].includes(m.role),
  )
  return (
    <div>
      <PageHeader title="Responders" subtitle="People who can handle incidents" />
      <div className="rounded-lg border border-[var(--color-border)] bg-white">
        <ul className="divide-y divide-[var(--color-border)]">
          {list.map((m) => (
            <li key={m.id} className="flex justify-between px-4 py-3 text-sm">
              <div>
                <p className="font-medium">{m.user_name}</p>
                <p className="text-slate-500">{m.user_phone || m.user_email}</p>
              </div>
              <span className="font-medium text-[var(--color-blue)]">{m.role}</span>
            </li>
          ))}
          {!list.length ? <li className="px-4 py-8 text-center text-slate-500">No responders</li> : null}
        </ul>
      </div>
    </div>
  )
}
