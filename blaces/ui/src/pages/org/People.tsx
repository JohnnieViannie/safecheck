import { useQuery } from '@tanstack/react-query'
import { useState } from 'react'
import { getErrorMessage, useAuth } from '../../api/auth'
import { peopleApi, unwrapList } from '../../api/services'
import type { Person } from '../../types'
import { NextOfKinPanel } from '../../components/NextOfKinPanel'
import {
  Button,
  EmptyState,
  ErrorState,
  LoadingState,
  Modal,
  PageHeader,
  SearchInput,
  StatusBadge,
} from '../../components/ui'

export function PeoplePage() {
  const { activeOrgId } = useAuth()
  const [search, setSearch] = useState('')
  const [kinFor, setKinFor] = useState<Person | null>(null)

  const query = useQuery({
    queryKey: ['people', activeOrgId, search],
    queryFn: async () =>
      unwrapList(
        (
          await peopleApi.list({
            ...(activeOrgId ? { organization: activeOrgId } : {}),
            search,
          })
        ).data,
      ),
  })

  if (query.isLoading) return <LoadingState />
  if (query.isError)
    return <ErrorState message={getErrorMessage(query.error)} onRetry={() => query.refetch()} />

  return (
    <div>
      <PageHeader
        title="Individuals"
        subtitle="People your organization protects. To add someone, contact SafeBangle."
      />
      <div className="mb-4">
        <SearchInput value={search} onChange={setSearch} placeholder="Search individuals…" />
      </div>
      {!query.data?.length ? (
        <EmptyState
          title={search ? 'No individuals match your search' : 'No individuals yet'}
          description="SafeBangle registers people and their bracelets for your organization."
        />
      ) : (
        <div className="console-card overflow-x-auto">
          <table className="min-w-[640px] w-full text-left text-sm">
            <thead className="bg-slate-50 text-slate-500">
              <tr>
                <th className="px-4 py-3 font-medium">Name</th>
                <th className="px-4 py-3 font-medium">Bracelet</th>
                <th className="px-4 py-3 font-medium">Status</th>
                <th className="px-4 py-3 font-medium">Last alert</th>
                <th className="px-4 py-3 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--color-border)]">
              {query.data.map((p) => (
                <tr key={p.id}>
                  <td className="px-4 py-3">
                    <div className="font-medium">{p.full_name}</div>
                    <div className="text-xs text-slate-500">{p.phone || p.email}</div>
                  </td>
                  <td className="px-4 py-3">
                    {p.current_bracelet ? (
                      <div>
                        <p className="font-medium">{p.current_bracelet.device_id}</p>
                        <StatusBadge status={p.current_bracelet.status} />
                      </div>
                    ) : (
                      <span className="text-slate-400">No bracelet</span>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <StatusBadge status={p.is_active ? 'Active' : 'Inactive'} />
                  </td>
                  <td className="px-4 py-3 text-slate-500">
                    {p.last_alert_at ? new Date(p.last_alert_at).toLocaleString() : 'None'}
                  </td>
                  <td className="px-4 py-3">
                    <Button variant="ghost" className="!px-2 !py-1" onClick={() => setKinFor(p)}>
                      Next of kin
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <Modal
        size="lg"
        open={!!kinFor}
        title={kinFor ? `Next of kin for ${kinFor.full_name}` : 'Next of kin'}
        onClose={() => setKinFor(null)}
      >
        {kinFor ? <NextOfKinPanel target={{ person: kinFor.id }} /> : null}
      </Modal>
    </div>
  )
}
