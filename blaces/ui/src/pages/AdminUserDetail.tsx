import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import { getErrorMessage, useAuth } from '../api/auth'
import { braceletApi, usersApi } from '../api/services'
import { NextOfKinPanel } from '../components/NextOfKinPanel'
import { PhoneInput, useDialCodes } from '../components/PhoneInput'
import { PhotoUploader } from '../components/PhotoUploader'
import {
  Button,
  ErrorState,
  Input,
  LoadingState,
  Modal,
  PageHeader,
  Select,
  StatusBadge,
} from '../components/ui'
import { EMPTY_PHONE, isValidNationalPhone, splitPhone, toE164, type PhoneValue } from '../lib/phone'

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="admin-card space-y-4 p-5 sm:p-6">
      <h2 className="text-base font-semibold text-[var(--color-charcoal)]">{title}</h2>
      {children}
    </section>
  )
}

function Detail({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs text-slate-400">{label}</dt>
      <dd className="break-words text-sm font-medium text-[var(--color-charcoal)]">{children}</dd>
    </div>
  )
}

export function AdminUserDetail() {
  const { id = '' } = useParams()
  const qc = useQueryClient()
  const navigate = useNavigate()
  const { user: me } = useAuth()
  const isAdmin = Boolean(me?.is_platform_admin)
  const dialCodes = useDialCodes()
  const [form, setForm] = useState({
    first_name: '',
    last_name: '',
    date_of_birth: '',
    city: '',
    country_code: '',
    address: '',
  })
  const [phone, setPhone] = useState<PhoneValue>(EMPTY_PHONE)
  const [deviceOpen, setDeviceOpen] = useState(false)
  const [device, setDevice] = useState({ device_id: '', old_device_state: 'broken', reason: '' })

  const query = useQuery({
    queryKey: ['admin-user', id],
    queryFn: async () => (await usersApi.get(id)).data,
  })
  const user = query.data

  useEffect(() => {
    if (!user) return
    const split = splitPhone(user.phone || '', dialCodes)
    setForm({
      first_name: user.first_name || '',
      last_name: user.last_name || '',
      date_of_birth: user.date_of_birth || '',
      city: user.city || '',
      country_code: user.country_code || '',
      address: user.address || '',
    })
    setPhone({
      country_code: split.country_code,
      dial_code: split.dial_code,
      national: user.phone ? split.phone_national : '',
    })
    // Only reload the form when a saved record arrives, not when dial codes finish loading.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user])

  const refresh = () => {
    void qc.invalidateQueries({ queryKey: ['admin-user', id] })
    void qc.invalidateQueries({ queryKey: ['admin-users'] })
    void qc.invalidateQueries({ queryKey: ['bracelets'] })
    void qc.invalidateQueries({ queryKey: ['people'] })
  }

  const save = useMutation({
    mutationFn: () =>
      usersApi.update(id, {
        first_name: form.first_name.trim(),
        last_name: form.last_name.trim(),
        phone: toE164(phone),
        date_of_birth: form.date_of_birth || null,
        city: form.city.trim(),
        country_code: form.country_code,
        address: form.address.trim(),
      }),
    onSuccess: () => {
      toast.success('User updated')
      refresh()
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const photo = useMutation({
    mutationFn: (file: File | null) =>
      file ? usersApi.uploadPhoto(id, file) : usersApi.removePhoto(id),
    onSuccess: () => {
      toast.success('Picture updated')
      refresh()
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const replace = useMutation({
    mutationFn: () =>
      usersApi.replaceDevice(id, {
        device_id: device.device_id.trim(),
        old_device_state: device.old_device_state,
        reason: device.reason.trim(),
      }),
    onSuccess: () => {
      toast.success(user?.current_device ? 'Device replaced' : 'Device added')
      setDeviceOpen(false)
      setDevice({ device_id: '', old_device_state: 'broken', reason: '' })
      refresh()
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const removeDevice = useMutation({
    mutationFn: () => braceletApi.unassign(user!.current_device!.id),
    onSuccess: () => {
      toast.success('Device removed. It can now be given to someone else.')
      refresh()
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const runAction = useMutation({
    mutationFn: (action: 'mute' | 'unmute' | 'block' | 'unblock' | 'delete') =>
      action === 'delete' ? usersApi.remove(id) : usersApi[action](id),
    onSuccess: (_data, action) => {
      const labels = {
        mute: 'User muted',
        unmute: 'User unmuted',
        block: 'User blocked',
        unblock: 'User unblocked',
        delete: 'User deleted',
      }
      toast.success(labels[action])
      if (action === 'delete') {
        void qc.invalidateQueries({ queryKey: ['admin-users'] })
        void qc.invalidateQueries({ queryKey: ['bracelets'] })
        navigate('/admin/users')
      } else {
        refresh()
      }
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  if (query.isLoading) return <LoadingState />
  if (query.isError || !user) {
    return <ErrorState message={getErrorMessage(query.error)} onRetry={() => query.refetch()} />
  }

  const status =
    user.status_label || (user.is_active === false ? 'blocked' : user.is_muted ? 'muted' : 'active')
  const hasDevice = Boolean(user.current_device)
  const phoneInvalid = Boolean(phone.national.trim()) && !isValidNationalPhone(phone.national)

  return (
    <div className="mx-auto max-w-5xl space-y-4">
      <Link
        to="/admin/users"
        className="inline-block text-sm font-medium text-[var(--color-blue)] hover:underline"
      >
        ← All users
      </Link>
      <PageHeader
        title={user.full_name || user.username}
        subtitle={`Username: ${user.username}`}
        actions={
          isAdmin && !user.is_platform_admin ? (
            <div className="flex flex-wrap gap-2">
              <Button
                variant="secondary"
                disabled={runAction.isPending}
                onClick={() => runAction.mutate(user.is_muted ? 'unmute' : 'mute')}
              >
                {user.is_muted ? 'Unmute' : 'Mute'}
              </Button>
              <Button
                variant="secondary"
                disabled={runAction.isPending}
                onClick={() => {
                  if (user.is_active === false) runAction.mutate('unblock')
                  else if (window.confirm(`Block ${user.full_name}? They won't be able to sign in.`)) {
                    runAction.mutate('block')
                  }
                }}
              >
                {user.is_active === false ? 'Unblock' : 'Block'}
              </Button>
              <Button
                variant="danger"
                disabled={runAction.isPending}
                onClick={() => {
                  if (
                    window.confirm(
                      `Permanently delete ${user.full_name}? This removes them and their next of kin, and frees their bracelet. Past alerts stay on record without their name. This can't be undone.`,
                    )
                  ) {
                    runAction.mutate('delete')
                  }
                }}
              >
                Delete
              </Button>
            </div>
          ) : undefined
        }
      />

      <Section title="Overview">
        <PhotoUploader
          name={user.full_name}
          photoUrl={user.photo_url}
          busy={photo.isPending}
          onUpload={(file) => photo.mutate(file)}
          onRemove={() => photo.mutate(null)}
          onError={(message) => toast.error(message)}
        />
        <dl className="grid grid-cols-2 gap-4 sm:grid-cols-3">
          <Detail label="Status">
            <StatusBadge status={status} />
          </Detail>
          <Detail label="Phone">
            {user.phone || '—'}
            {user.phone && !user.phone_verified ? (
              <span className="block text-[11px] font-normal text-amber-600">Not verified</span>
            ) : null}
          </Detail>
          <Detail label="Email">{user.email || '—'}</Detail>
          <Detail label="Organization">
            {user.memberships?.length
              ? user.memberships.map((m) => `${m.organization_name} (${m.role})`).join(', ')
              : user.organization_name || 'Independent'}
          </Detail>
          <Detail label="Registered by">{user.registered_by_name || '—'}</Detail>
          <Detail label="Joined">{new Date(user.created_at).toLocaleDateString()}</Detail>
        </dl>
      </Section>

      <Section title="Device">
        {user.current_device ? (
          <dl className="grid grid-cols-2 gap-4 sm:grid-cols-3">
            <Detail label="Device ID">
              <span className="font-mono">{user.current_device.device_id}</span>
            </Detail>
            <Detail label="Status">
              <StatusBadge status={user.current_device.status} />
            </Detail>
            <Detail label="Last alert">
              {user.current_device.last_alert_at
                ? new Date(user.current_device.last_alert_at).toLocaleString()
                : 'None'}
            </Detail>
          </dl>
        ) : user.is_platform_admin ||
          user.platform_role === 'registrar' ||
          user.account_type === 'organization' ? (
          <p className="text-sm text-slate-500">Staff accounts don't need a bracelet.</p>
        ) : (
          <p className="rounded-xl bg-amber-50 px-3 py-2 text-sm font-medium text-amber-700">
            No bracelet. This person isn't protected until one is added.
          </p>
        )}
        <div className="flex flex-wrap gap-2">
          <Button variant={hasDevice ? 'secondary' : 'primary'} onClick={() => setDeviceOpen(true)}>
            {hasDevice ? 'Replace device' : 'Add device'}
          </Button>
          {hasDevice && isAdmin ? (
            <Button
              variant="ghost"
              className="text-[var(--color-red)]"
              disabled={removeDevice.isPending}
              onClick={() => {
                if (
                  window.confirm(
                    `Remove ${user.current_device?.device_id} from ${user.full_name}? They won't be protected until they get another bracelet.`,
                  )
                ) {
                  removeDevice.mutate()
                }
              }}
            >
              Remove device
            </Button>
          ) : null}
        </div>
        {user.device_history.length ? (
          <div className="overflow-x-auto rounded-2xl border border-[var(--color-border)]">
            <table className="min-w-[560px] w-full text-left text-sm">
              <caption className="sr-only">Device history</caption>
              <thead className="bg-slate-50/80 text-slate-500">
                <tr>
                  <th className="px-4 py-2.5 font-medium">Device</th>
                  <th className="px-4 py-2.5 font-medium">From</th>
                  <th className="px-4 py-2.5 font-medium">Until</th>
                  <th className="px-4 py-2.5 font-medium">Reason</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-black/[0.04] bg-white">
                {user.device_history.map((h) => (
                  <tr key={h.id}>
                    <td className="px-4 py-2.5 font-mono">{h.device_id}</td>
                    <td className="px-4 py-2.5 text-slate-500">
                      {new Date(h.assigned_at).toLocaleDateString()}
                    </td>
                    <td className="px-4 py-2.5 text-slate-500">
                      {h.unassigned_at ? new Date(h.unassigned_at).toLocaleDateString() : 'Current'}
                    </td>
                    <td className="px-4 py-2.5 text-slate-500">{h.reason || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
      </Section>

      <Section title="Details and address">
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">First name</span>
            <Input
              value={form.first_name}
              onChange={(e) => setForm({ ...form, first_name: e.target.value })}
            />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Last name</span>
            <Input
              value={form.last_name}
              onChange={(e) => setForm({ ...form, last_name: e.target.value })}
            />
          </label>
        </div>
        <div className="space-y-1.5">
          <span className="text-sm font-medium">Phone</span>
          <PhoneInput value={phone} onChange={setPhone} />
          {phoneInvalid ? (
            <p className="text-sm text-[var(--color-red)]">Enter a valid phone number.</p>
          ) : null}
        </div>
        <label className="block space-y-1.5">
          <span className="text-sm font-medium">Date of birth</span>
          <Input
            type="date"
            max={new Date().toISOString().slice(0, 10)}
            value={form.date_of_birth}
            onChange={(e) => setForm({ ...form, date_of_birth: e.target.value })}
          />
        </label>
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">City or town</span>
            <Input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Country</span>
            <Select
              value={form.country_code}
              onChange={(e) => setForm({ ...form, country_code: e.target.value })}
            >
              <option value="">Select</option>
              {dialCodes.map((c) => (
                <option key={c.iso2} value={c.iso2}>
                  {c.name}
                </option>
              ))}
            </Select>
          </label>
        </div>
        <label className="block space-y-1.5">
          <span className="text-sm font-medium">Street address</span>
          <Input
            value={form.address}
            onChange={(e) => setForm({ ...form, address: e.target.value })}
          />
        </label>
        <Button disabled={save.isPending || phoneInvalid} onClick={() => save.mutate()}>
          {save.isPending ? 'Saving…' : 'Save changes'}
        </Button>
      </Section>

      <Section title="Next of kin">
        <NextOfKinPanel
          target={user.person_id ? { person: user.person_id } : { ownerUser: user.id }}
        />
      </Section>

      <Modal
        open={deviceOpen}
        title={hasDevice ? 'Replace device' : 'Add device'}
        onClose={() => setDeviceOpen(false)}
      >
        <div className="space-y-3">
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">New device ID</span>
            <Input
              placeholder="SB-0002"
              value={device.device_id}
              onChange={(e) => setDevice({ ...device, device_id: e.target.value })}
            />
          </label>
          {hasDevice ? (
            <label className="block space-y-1.5">
              <span className="text-sm font-medium">
                What happens to {user.current_device?.device_id}?
              </span>
              <Select
                value={device.old_device_state}
                onChange={(e) => setDevice({ ...device, old_device_state: e.target.value })}
              >
                <option value="broken">It's broken or lost: deactivate it</option>
                <option value="spare">It still works: keep it as a spare</option>
              </Select>
            </label>
          ) : null}
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Reason (optional)</span>
            <Input
              value={device.reason}
              onChange={(e) => setDevice({ ...device, reason: e.target.value })}
            />
          </label>
          <Button
            className="w-full"
            disabled={!device.device_id.trim() || replace.isPending}
            onClick={() => replace.mutate()}
          >
            {replace.isPending ? 'Saving…' : hasDevice ? 'Replace device' : 'Add device'}
          </Button>
        </div>
      </Modal>
    </div>
  )
}
