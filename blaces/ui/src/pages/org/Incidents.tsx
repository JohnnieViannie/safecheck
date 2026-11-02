import { AlertLocation } from '../../components/AlertLocation'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { getErrorMessage, useAuth } from '../../api/auth'
import { incidentApi, unwrapList } from '../../api/services'
import {
  Button,
  ErrorState,
  Input,
  LoadingState,
  PageHeader,
  SearchInput,
  StatusBadge,
  Textarea,
} from '../../components/ui'
import { useState } from 'react'

export function IncidentsPage({ scoped = true }: { scoped?: boolean }) {
  const { activeOrgId } = useAuth()
  const [search, setSearch] = useState('')
  const params: Record<string, string> = { search, ordering: '-created_at' }
  if (scoped && activeOrgId) params.organization = activeOrgId

  const query = useQuery({
    queryKey: ['incidents', params],
    queryFn: async () => unwrapList((await incidentApi.list(params)).data),
    refetchInterval: 5000,
  })

  if (query.isLoading) return <LoadingState />
  if (query.isError) return <ErrorState message={getErrorMessage(query.error)} onRetry={() => query.refetch()} />

  return (
    <div>
      <PageHeader title="Incidents" subtitle="Response workflows" />
      <div className="mb-4">
        <SearchInput value={search} onChange={setSearch} />
      </div>
      {!query.data?.length ? (
        <p className="rounded-lg border border-dashed border-[var(--color-border)] bg-white py-12 text-center text-sm text-slate-500">
          No incidents yet.
        </p>
      ) : (
        <div className="console-card overflow-x-auto">
          <table className="min-w-[560px] w-full text-left text-sm">
            <thead className="bg-slate-50 text-slate-500">
              <tr>
                <th className="px-4 py-3 font-medium">Person</th>
                <th className="px-4 py-3 font-medium">Alert</th>
                <th className="px-4 py-3 font-medium">Responder</th>
                <th className="px-4 py-3 font-medium">Status</th>
                <th className="px-4 py-3 font-medium">Created</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--color-border)]">
              {query.data.map((i) => (
                <tr key={i.id} className={i.status === 'NEW' ? 'bg-[var(--color-red-soft)]/50' : ''}>
                  <td className="px-4 py-3">
                    <Link className="font-medium text-[var(--color-blue)]" to={`${i.id}`}>
                      {i.person_name || 'Unknown'}
                    </Link>
                  </td>
                  <td className="px-4 py-3">{i.alert_code}</td>
                  <td className="px-4 py-3">{i.assigned_responder_email || '—'}</td>
                  <td className="px-4 py-3">
                    <StatusBadge status={i.status} />
                  </td>
                  <td className="px-4 py-3">{new Date(i.created_at).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

export function IncidentDetailPage() {
  const { id } = useParams()
  const qc = useQueryClient()
  const [note, setNote] = useState('')
  const [resolution, setResolution] = useState('')

  const query = useQuery({
    queryKey: ['incident', id],
    queryFn: async () => (await incidentApi.get(id!)).data,
    enabled: !!id,
    refetchInterval: 5000,
  })

  const mutate = useMutation({
    mutationFn: async (action: string) => {
      if (!id) return
      if (action === 'acknowledge') return incidentApi.acknowledge(id, note)
      if (action === 'assign') return incidentApi.assign(id)
      if (action === 'respond') return incidentApi.respond(id)
      if (action === 'resolve') return incidentApi.resolve(id, resolution)
      if (action === 'close') return incidentApi.close(id)
      if (action === 'note') return incidentApi.addNote(id, note)
    },
    onSuccess: () => {
      toast.success('Incident updated')
      void qc.invalidateQueries({ queryKey: ['incident', id] })
      void qc.invalidateQueries({ queryKey: ['incidents'] })
      setNote('')
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  if (query.isLoading) return <LoadingState />
  if (query.isError || !query.data)
    return <ErrorState message={getErrorMessage(query.error)} onRetry={() => query.refetch()} />

  const i = query.data
  return (
    <div>
      <PageHeader
        title={`Incident · ${i.person_name || 'Unknown'}`}
        subtitle={`${i.alert_code} · ${i.device_id || ''}`}
        actions={<StatusBadge status={i.status} />}
      />
      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-4 lg:col-span-2">
          <div className="rounded-lg border border-[var(--color-border)] bg-white p-4">
            <h3 className="font-semibold">Details</h3>
            <dl className="mt-3 grid gap-2 text-sm sm:grid-cols-2">
              <div>
                <dt className="text-slate-500">Location</dt>
                <dd>
                  <AlertLocation alert={i} />
                </dd>
              </div>
              <div>
                <dt className="text-slate-500">Responder</dt>
                <dd>{i.assigned_responder_email || 'Unassigned'}</dd>
              </div>
              <div>
                <dt className="text-slate-500">Acknowledged</dt>
                <dd>{i.acknowledged_at ? new Date(i.acknowledged_at).toLocaleString() : '—'}</dd>
              </div>
              <div>
                <dt className="text-slate-500">Resolved</dt>
                <dd>{i.resolved_at ? new Date(i.resolved_at).toLocaleString() : '—'}</dd>
              </div>
            </dl>
            {i.resolution ? (
              <p className="mt-3 text-sm">
                <span className="font-medium">Resolution:</span> {i.resolution}
              </p>
            ) : null}
          </div>
          <div className="rounded-lg border border-[var(--color-border)] bg-white p-4">
            <h3 className="font-semibold">Timeline</h3>
            <ul className="mt-3 space-y-3">
              {i.events?.map((e) => (
                <li key={e.id} className="border-l-2 border-[var(--color-blue)] pl-3 text-sm">
                  <p className="font-medium">
                    {e.action} {e.to_status ? `→ ${e.to_status}` : ''}
                  </p>
                  <p className="text-slate-500">
                    {e.actor_email || 'System'} · {new Date(e.created_at).toLocaleString()}
                  </p>
                  {e.note ? <p className="mt-1">{e.note}</p> : null}
                </li>
              ))}
            </ul>
          </div>
        </div>
        <div className="space-y-3 rounded-lg border border-[var(--color-border)] bg-white p-4">
          <h3 className="font-semibold">Actions</h3>
          <Button className="w-full" onClick={() => mutate.mutate('acknowledge')}>
            Acknowledge
          </Button>
          <Button className="w-full" variant="secondary" onClick={() => mutate.mutate('assign')}>
            Assign to me
          </Button>
          <Button className="w-full" variant="secondary" onClick={() => mutate.mutate('respond')}>
            Start responding
          </Button>
          <Textarea
            placeholder="Resolution notes"
            value={resolution}
            onChange={(e) => setResolution(e.target.value)}
          />
          <Button className="w-full" onClick={() => mutate.mutate('resolve')} disabled={!resolution}>
            Resolve
          </Button>
          <Button className="w-full" variant="secondary" onClick={() => mutate.mutate('close')}>
            Close
          </Button>
          <Input placeholder="Add note" value={note} onChange={(e) => setNote(e.target.value)} />
          <Button className="w-full" variant="ghost" disabled={!note} onClick={() => mutate.mutate('note')}>
            Add note
          </Button>
        </div>
      </div>
    </div>
  )
}
