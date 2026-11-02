import { AlertLocation } from '../../components/AlertLocation'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { getErrorMessage, useAuth } from '../../api/auth'
import { alertApi, unwrapList } from '../../api/services'
import { ErrorState, LoadingState, PageHeader, SearchInput, StatusBadge } from '../../components/ui'
import { useState } from 'react'

export function AlertsPage({ scoped = true }: { scoped?: boolean }) {
  const { activeOrgId } = useAuth()
  const [search, setSearch] = useState('')
  const params: Record<string, string> = { search, ordering: '-received_at' }
  if (scoped && activeOrgId) params.organization = activeOrgId

  const query = useQuery({
    queryKey: ['alerts', params],
    queryFn: async () => unwrapList((await alertApi.list(params)).data),
    refetchInterval: 5000,
  })

  if (query.isLoading) return <LoadingState />
  if (query.isError) return <ErrorState message={getErrorMessage(query.error)} onRetry={() => query.refetch()} />

  return (
    <div>
      <PageHeader title="Alerts" subtitle="Emergency events from bracelets" />
      <div className="mb-4">
        <SearchInput value={search} onChange={setSearch} />
      </div>
      {!query.data?.length ? (
        <p className="rounded-lg border border-dashed border-[var(--color-border)] bg-white py-12 text-center text-sm text-slate-500">
          No alerts received yet.
        </p>
      ) : (
        <div className="console-card overflow-x-auto">
          <table className="min-w-[640px] w-full text-left text-sm">
            <thead className="bg-slate-50 text-slate-500">
              <tr>
                <th className="px-4 py-3 font-medium">Person</th>
                <th className="px-4 py-3 font-medium">Bracelet</th>
                <th className="px-4 py-3 font-medium">Type</th>
                <th className="px-4 py-3 font-medium">Location</th>
                <th className="px-4 py-3 font-medium">Time</th>
                <th className="px-4 py-3 font-medium">Incident</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--color-border)]">
              {query.data.map((a) => (
                <tr key={a.id} className={a.alert_code === 'SOS' ? 'bg-[var(--color-red-soft)]/40' : ''}>
                  <td className="px-4 py-3 font-medium">{a.person_name || '—'}</td>
                  <td className="px-4 py-3">{a.device_id}</td>
                  <td className="px-4 py-3">
                    <StatusBadge status={a.alert_code} />
                  </td>
                  <td className="px-4 py-3">
                    <AlertLocation alert={a} />
                  </td>
                  <td className="px-4 py-3">{new Date(a.received_at).toLocaleString()}</td>
                  <td className="px-4 py-3">
                    {a.incident_id ? (
                      <Link className="text-[var(--color-blue)]" to={`../incidents/${a.incident_id}`}>
                        Open
                      </Link>
                    ) : (
                      '—'
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
