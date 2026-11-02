import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { getErrorMessage } from '../api/auth'
import { orgApi, peopleApi, unwrapList } from '../api/services'
import { AddUserModal } from '../components/AddUserModal'
import { NextOfKinPanel } from '../components/NextOfKinPanel'
import { PhoneInput, useDialCodes } from '../components/PhoneInput'
import { StaffInviteForm } from '../components/StaffInviteForm'
import {
  Button,
  ErrorState,
  Input,
  LoadingState,
  Modal,
  PageHeader,
  SearchInput,
  Select,
  StatusBadge,
} from '../components/ui'
import { EMPTY_PHONE, isValidEmail, isValidNationalPhone, splitPhone, toE164, type PhoneValue } from '../lib/phone'
import type { Person } from '../types'

type Tab = 'members' | 'staff'

const ROLES = ['OWNER', 'ADMIN', 'STAFF', 'RESPONDER', 'VIEWER']

export function AdminOrganizationDetail() {
  const { id = '' } = useParams()
  const [tab, setTab] = useState<Tab>('members')
  const [search, setSearch] = useState('')
  const [adding, setAdding] = useState(false)
  const [kinFor, setKinFor] = useState<Person | null>(null)
  const [editing, setEditing] = useState<Person | null>(null)
  const [editForm, setEditForm] = useState({ first_name: '', last_name: '', email: '' })
  const [editPhone, setEditPhone] = useState<PhoneValue>(EMPTY_PHONE)
  const [editError, setEditError] = useState('')
  const qc = useQueryClient()
  const dialCodes = useDialCodes()

  const refreshPeople = () => {
    void qc.invalidateQueries({ queryKey: ['people'] })
    void qc.invalidateQueries({ queryKey: ['org', id] })
    void qc.invalidateQueries({ queryKey: ['admin-orgs'] })
    void qc.invalidateQueries({ queryKey: ['admin-users'] })
  }
  const refreshStaff = () => {
    void qc.invalidateQueries({ queryKey: ['org-members', id] })
    void qc.invalidateQueries({ queryKey: ['org', id] })
    void qc.invalidateQueries({ queryKey: ['admin-orgs'] })
  }

  const removeMember = useMutation({
    mutationFn: (personId: string) => peopleApi.removeFromOrganization(personId),
    onSuccess: ({ data }) => {
      toast.success(
        data.outcome === 'independent'
          ? 'Removed. They keep their account and bracelet as an independent user.'
          : 'Member removed and their bracelet freed.',
      )
      refreshPeople()
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const saveMember = useMutation({
    mutationFn: () =>
      peopleApi.update(editing!.id, {
        first_name: editForm.first_name.trim(),
        last_name: editForm.last_name.trim(),
        email: editForm.email.trim(),
        phone: toE164(editPhone),
      }),
    onSuccess: () => {
      toast.success('Member updated')
      setEditing(null)
      refreshPeople()
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const changeRole = useMutation({
    mutationFn: ({ membershipId, role }: { membershipId: string; role: string }) =>
      orgApi.updateMember(id, membershipId, role),
    onSuccess: () => {
      toast.success('Role updated')
      refreshStaff()
    },
    onError: (e) => {
      toast.error(getErrorMessage(e))
      refreshStaff()
    },
  })

  const removeStaff = useMutation({
    mutationFn: (membershipId: string) => orgApi.removeMember(id, membershipId),
    onSuccess: () => {
      toast.success('Staff member removed')
      refreshStaff()
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const openEdit = (person: Person) => {
    const split = splitPhone(person.phone || '', dialCodes)
    setEditing(person)
    setEditError('')
    setEditForm({
      first_name: person.first_name || '',
      last_name: person.last_name || '',
      email: person.email || '',
    })
    setEditPhone({
      country_code: split.country_code,
      dial_code: split.dial_code,
      national: person.phone ? split.phone_national : '',
    })
  }

  const submitEdit = () => {
    if (!editForm.first_name.trim()) return setEditError('Enter a first name.')
    if (!isValidNationalPhone(editPhone.national)) return setEditError('Enter a valid phone number.')
    if (!isValidEmail(editForm.email)) return setEditError('Enter a valid email, or leave it empty.')
    setEditError('')
    saveMember.mutate()
  }

  const org = useQuery({
    queryKey: ['org', id],
    queryFn: async () => (await orgApi.get(id)).data,
  })
  const people = useQuery({
    queryKey: ['people', id, search],
    queryFn: async () =>
      unwrapList((await peopleApi.list({ organization: id, search, page_size: '200' })).data),
    placeholderData: keepPreviousData,
  })
  const staff = useQuery({
    queryKey: ['org-members', id],
    queryFn: async () => (await orgApi.members(id)).data,
    enabled: tab === 'staff',
  })
  const invitations = useQuery({
    queryKey: ['org-invites', id],
    queryFn: async () => (await orgApi.invitations(id)).data,
    enabled: tab === 'staff',
  })

  if (org.isLoading) return <LoadingState />
  if (org.isError || !org.data) {
    return <ErrorState message={getErrorMessage(org.error)} onRetry={() => org.refetch()} />
  }
  const o = org.data
  const pendingInvites = (invitations.data || []).filter((inv) => inv.is_valid)

  return (
    <div className="mx-auto max-w-7xl space-y-4">
      <Link
        to="/admin/organizations"
        className="inline-block text-sm font-medium text-[var(--color-blue)] hover:underline"
      >
        ← All organizations
      </Link>
      <PageHeader
        title={o.name}
        subtitle={[o.phone, o.email, o.address].filter(Boolean).join(' · ') || o.description}
        actions={tab === 'members' ? <Button onClick={() => setAdding(true)}>Add member</Button> : undefined}
      />

      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge status={o.is_active === false ? 'blocked' : 'active'} />
        <span className="text-sm text-slate-500">
          {o.people_count} {o.people_count === 1 ? 'member' : 'members'} · {o.member_count} staff
        </span>
      </div>

      <div role="tablist" aria-label="Organization people" className="flex gap-1 border-b border-[var(--color-border)]">
        {(
          [
            ['members', 'Members'],
            ['staff', 'Staff'],
          ] as [Tab, string][]
        ).map(([value, label]) => (
          <button
            key={value}
            type="button"
            role="tab"
            aria-selected={tab === value}
            onClick={() => setTab(value)}
            className={`-mb-px border-b-2 px-4 py-2.5 text-sm font-semibold transition ${
              tab === value
                ? 'border-[var(--color-blue)] text-[var(--color-blue)]'
                : 'border-transparent text-slate-500 hover:text-[var(--color-charcoal)]'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {tab === 'members' ? (
        <div className="admin-card p-4 sm:p-5">
          <div className="mb-4">
            <SearchInput value={search} onChange={setSearch} placeholder="Search members…" />
          </div>
          {people.isLoading && !people.data ? (
            <LoadingState label="Loading members…" />
          ) : people.isError ? (
            <ErrorState message={getErrorMessage(people.error)} onRetry={() => people.refetch()} />
          ) : !people.data?.length ? (
            <p className="rounded-2xl border border-dashed border-[var(--color-border)] py-12 text-center text-sm text-slate-500">
              {search ? 'No members match your search.' : 'No members yet. Add the first one.'}
            </p>
          ) : (
            <div className="overflow-x-auto rounded-2xl border border-[var(--color-border)]">
              <table className="min-w-[640px] w-full text-left text-sm">
                <thead className="bg-slate-50/80 text-slate-500">
                  <tr>
                    <th className="px-5 py-3.5 font-medium">Name</th>
                    <th className="px-5 py-3.5 font-medium">Phone</th>
                    <th className="px-5 py-3.5 font-medium">Bracelet</th>
                    <th className="px-5 py-3.5 font-medium">Status</th>
                    <th className="px-5 py-3.5 font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-black/[0.04] bg-white">
                  {people.data.map((p) => (
                    <tr key={p.id} className="align-top hover:bg-slate-50/70">
                      <td className="px-5 py-3.5">
                        <p className="font-medium text-[var(--color-charcoal)]">{p.full_name}</p>
                        {p.email ? <p className="text-xs text-slate-500">{p.email}</p> : null}
                      </td>
                      <td className="whitespace-nowrap px-5 py-3.5">{p.phone || '—'}</td>
                      <td className="px-5 py-3.5">
                        {p.current_bracelet ? (
                          p.current_bracelet.device_id
                        ) : (
                          <span className="text-slate-400">No bracelet</span>
                        )}
                      </td>
                      <td className="px-5 py-3.5">
                        <StatusBadge status={p.is_active ? 'Active' : 'Inactive'} />
                      </td>
                      <td className="px-5 py-3.5">
                        <div className="flex flex-wrap gap-1.5">
                          <Button
                            variant="secondary"
                            className="px-2.5 py-1.5 text-xs"
                            onClick={() => setKinFor(p)}
                          >
                            Next of kin
                          </Button>
                          {p.linked_user ? (
                            <Link
                              to={`/admin/users/${p.linked_user}`}
                              className="inline-flex items-center rounded-xl border border-[var(--color-border)] bg-white px-2.5 py-1.5 text-xs font-semibold text-[var(--color-charcoal)] hover:bg-slate-50"
                            >
                              Manage
                            </Link>
                          ) : (
                            <Button
                              variant="secondary"
                              className="px-2.5 py-1.5 text-xs"
                              onClick={() => openEdit(p)}
                            >
                              Edit
                            </Button>
                          )}
                          <Button
                            variant="ghost"
                            className="px-2.5 py-1.5 text-xs text-[var(--color-red)]"
                            disabled={removeMember.isPending}
                            onClick={() => {
                              const message = p.linked_user
                                ? `Remove ${p.full_name} from ${o.name}? They keep their account and bracelet as an independent user.`
                                : `Remove ${p.full_name} from ${o.name}? Their record is deleted and their bracelet freed.`
                              if (window.confirm(message)) removeMember.mutate(p.id)
                            }}
                          >
                            Remove
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
      ) : (
        <div className="grid gap-4 lg:grid-cols-3">
          <div className="admin-card p-4 sm:p-5 lg:col-span-2">
            <h2 className="mb-3 font-semibold text-[var(--color-charcoal)]">Dashboard logins</h2>
            {staff.isLoading ? (
              <LoadingState label="Loading staff…" />
            ) : staff.isError ? (
              <ErrorState message={getErrorMessage(staff.error)} onRetry={() => staff.refetch()} />
            ) : !staff.data?.length ? (
              <p className="py-6 text-center text-sm text-slate-500">No staff yet.</p>
            ) : (
              <ul className="divide-y divide-black/[0.04]">
                {staff.data.map((m) => (
                  <li key={m.id} className="flex items-start justify-between gap-3 py-3">
                    <div className="min-w-0">
                      <p className="font-medium text-[var(--color-charcoal)]">{m.user_name}</p>
                      <p className="text-xs text-slate-500">
                        {[m.user_phone, m.user_email].filter(Boolean).join(' · ')}
                      </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-1.5">
                      <Select
                        aria-label={`Role for ${m.user_name}`}
                        className="!py-1.5 text-xs"
                        value={m.role}
                        disabled={changeRole.isPending}
                        onChange={(e) =>
                          changeRole.mutate({ membershipId: m.id, role: e.target.value })
                        }
                      >
                        {ROLES.map((role) => (
                          <option key={role} value={role}>
                            {role}
                          </option>
                        ))}
                      </Select>
                      <Button
                        variant="ghost"
                        className="px-2.5 py-1.5 text-xs text-[var(--color-red)]"
                        disabled={removeStaff.isPending}
                        onClick={() => {
                          if (window.confirm(`Remove ${m.user_name} from ${o.name}'s staff?`)) {
                            removeStaff.mutate(m.id)
                          }
                        }}
                      >
                        Remove
                      </Button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
            {pendingInvites.length ? (
              <>
                <h3 className="mb-2 mt-5 text-sm font-semibold text-[var(--color-charcoal)]">
                  Pending invitations
                </h3>
                <ul className="space-y-1 text-sm">
                  {pendingInvites.map((inv) => (
                    <li key={inv.id} className="flex justify-between gap-3">
                      <span className="min-w-0 truncate">{inv.phone || inv.email}</span>
                      <span className="shrink-0 text-slate-500">{inv.role}</span>
                    </li>
                  ))}
                </ul>
              </>
            ) : null}
          </div>
          <div className="admin-card p-4 sm:p-5">
            <h2 className="mb-3 font-semibold text-[var(--color-charcoal)]">Add staff</h2>
            <StaffInviteForm organizationId={id} addExisting />
          </div>
        </div>
      )}

      <AddUserModal
        open={adding}
        title={`Add member to ${o.name}`}
        organizationId={id}
        onClose={() => setAdding(false)}
      />
      <Modal open={Boolean(editing)} title="Edit member" onClose={() => setEditing(null)}>
        <div className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="block space-y-1.5">
              <span className="text-sm font-medium">First name</span>
              <Input
                value={editForm.first_name}
                onChange={(e) => setEditForm({ ...editForm, first_name: e.target.value })}
              />
            </label>
            <label className="block space-y-1.5">
              <span className="text-sm font-medium">Last name</span>
              <Input
                value={editForm.last_name}
                onChange={(e) => setEditForm({ ...editForm, last_name: e.target.value })}
              />
            </label>
          </div>
          <div className="space-y-1.5">
            <span className="text-sm font-medium">Phone</span>
            <PhoneInput value={editPhone} onChange={setEditPhone} />
          </div>
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Email (optional)</span>
            <Input
              type="email"
              value={editForm.email}
              onChange={(e) => setEditForm({ ...editForm, email: e.target.value })}
            />
          </label>
          {editError ? <p className="text-sm text-[var(--color-red)]">{editError}</p> : null}
          <Button className="w-full" disabled={saveMember.isPending} onClick={submitEdit}>
            {saveMember.isPending ? 'Saving…' : 'Save changes'}
          </Button>
        </div>
      </Modal>
      <Modal
        size="lg"
        open={Boolean(kinFor)}
        title={kinFor ? `Next of kin for ${kinFor.full_name}` : 'Next of kin'}
        onClose={() => setKinFor(null)}
      >
        {kinFor ? <NextOfKinPanel target={{ person: kinFor.id }} /> : null}
      </Modal>
    </div>
  )
}
