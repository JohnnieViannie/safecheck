import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Link } from 'react-router-dom'
import { getErrorMessage } from '../api/auth'
import { orgApi, unwrapList, usersApi } from '../api/services'
import { EMPTY_PHONE, isValidEmail, isValidNationalPhone, toE164, type PhoneValue } from '../lib/phone'
import type { CreatedUser } from '../types'
import { PhoneInput, useDialCodes } from './PhoneInput'
import { Button, Input, Modal, Select } from './ui'

const EMPTY_FORM = {
  first_name: '',
  last_name: '',
  email: '',
  date_of_birth: '',
  city: '',
  country_code: '',
  address: '',
  device_id: '',
  organization: '',
}

/**
 * Staff register a person and give them their bracelet in one step.
 * With `organizationId`, the person joins that organization.
 */
export function AddUserModal({
  open,
  title,
  organizationId,
  onClose,
  onCreated,
}: {
  open: boolean
  title: string
  organizationId?: string
  onClose: () => void
  onCreated?: (user: CreatedUser) => void
}) {
  const qc = useQueryClient()
  const dialCodes = useDialCodes()
  const [form, setForm] = useState(EMPTY_FORM)
  const [phone, setPhone] = useState<PhoneValue>(EMPTY_PHONE)
  const [formError, setFormError] = useState('')
  const [created, setCreated] = useState<CreatedUser | null>(null)

  const orgs = useQuery({
    queryKey: ['admin-orgs-filter'],
    queryFn: async () => unwrapList((await orgApi.list({ page_size: '200' })).data),
    enabled: open && !organizationId,
  })

  const create = useMutation({
    mutationFn: async () =>
      (
        await usersApi.create({
          first_name: form.first_name.trim(),
          last_name: form.last_name.trim(),
          phone: toE164(phone),
          email: form.email.trim(),
          date_of_birth: form.date_of_birth,
          city: form.city.trim(),
          country_code: form.country_code || phone.country_code,
          address: form.address.trim(),
          device_id: form.device_id.trim(),
          organization: organizationId || form.organization || null,
        })
      ).data,
    onSuccess: (data) => {
      setCreated(data)
      onCreated?.(data)
      setForm(EMPTY_FORM)
      setPhone((p) => ({ ...p, national: '' }))
      void qc.invalidateQueries({ queryKey: ['admin-users'] })
      void qc.invalidateQueries({ queryKey: ['admin-dashboard'] })
      void qc.invalidateQueries({ queryKey: ['admin-orgs'] })
      void qc.invalidateQueries({ queryKey: ['org'] })
      void qc.invalidateQueries({ queryKey: ['people'] })
      void qc.invalidateQueries({ queryKey: ['bracelets'] })
    },
    onError: (e) => setFormError(getErrorMessage(e)),
  })

  const close = () => {
    setCreated(null)
    setFormError('')
    onClose()
  }

  const today = new Date().toISOString().slice(0, 10)

  const submit = () => {
    if (!form.first_name.trim()) return setFormError('Enter a first name.')
    if (!isValidNationalPhone(phone.national)) return setFormError('Enter a valid phone number.')
    if (!isValidEmail(form.email)) return setFormError('Enter a valid email, or leave it empty.')
    if (!form.date_of_birth) return setFormError('Enter their date of birth.')
    if (form.date_of_birth > today) return setFormError("Date of birth can't be in the future.")
    if (!form.city.trim()) return setFormError('Enter the city or town where they live.')
    if (!form.device_id.trim()) return setFormError("Enter their bracelet's device ID.")
    setFormError('')
    create.mutate()
  }

  if (created) {
    return (
      <Modal open={open} title="User registered" onClose={close}>
        <div className="space-y-3">
          <p className="text-sm text-slate-600">
            {created.full_name} is registered with bracelet{' '}
            <span className="font-medium">{created.device_id}</span>.
          </p>
          <div className="rounded-2xl bg-slate-50/80 p-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-slate-400">Username</p>
            <p className="mt-1 font-mono text-lg font-semibold text-[var(--color-charcoal)]">
              {created.username}
            </p>
          </div>
          {created.sms_sent ? (
            <p className="text-sm text-slate-600">
              We texted them this username and how to set their password.
            </p>
          ) : (
            <p className="text-sm text-amber-700">
              We couldn't text them. Share this username and ask them to set a password on the
              sign-in page, under "Set or reset password".
            </p>
          )}
          <div className="flex gap-2">
            <Link
              to={`/admin/users/${created.id}`}
              onClick={close}
              className="inline-flex flex-1 items-center justify-center rounded-xl border border-[var(--color-border)] bg-white px-3 py-2 text-sm font-semibold text-[var(--color-charcoal)] hover:bg-slate-50"
            >
              Open profile
            </Link>
            <Button className="flex-1" onClick={close}>
              Done
            </Button>
          </div>
        </div>
      </Modal>
    )
  }

  return (
    <Modal open={open} title={title} onClose={close}>
      <div className="space-y-3">
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
        </div>
        <label className="block space-y-1.5">
          <span className="text-sm font-medium">Email (optional)</span>
          <Input
            type="email"
            value={form.email}
            onChange={(e) => setForm({ ...form, email: e.target.value })}
          />
        </label>
        <label className="block space-y-1.5">
          <span className="text-sm font-medium">Date of birth</span>
          <Input
            type="date"
            max={today}
            value={form.date_of_birth}
            onChange={(e) => setForm({ ...form, date_of_birth: e.target.value })}
          />
        </label>
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">City or town</span>
            <Input
              placeholder="Kampala"
              value={form.city}
              onChange={(e) => setForm({ ...form, city: e.target.value })}
            />
          </label>
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Country</span>
            <Select
              value={form.country_code || phone.country_code}
              onChange={(e) => setForm({ ...form, country_code: e.target.value })}
            >
              {dialCodes.map((c) => (
                <option key={c.iso2} value={c.iso2}>
                  {c.name}
                </option>
              ))}
            </Select>
          </label>
        </div>
        <label className="block space-y-1.5">
          <span className="text-sm font-medium">Street address (optional)</span>
          <Input
            value={form.address}
            onChange={(e) => setForm({ ...form, address: e.target.value })}
          />
        </label>
        {!organizationId ? (
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Organization</span>
            <Select
              value={form.organization}
              onChange={(e) => setForm({ ...form, organization: e.target.value })}
            >
              <option value="">Independent (no organization)</option>
              {orgs.data?.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </Select>
          </label>
        ) : null}
        <label className="block space-y-1.5 rounded-2xl bg-slate-50/80 p-3">
          <span className="text-sm font-semibold text-[var(--color-charcoal)]">Bracelet device ID</span>
          <Input
            placeholder="SB-0001"
            value={form.device_id}
            onChange={(e) => setForm({ ...form, device_id: e.target.value })}
          />
          <span className="block text-xs text-slate-500">
            New IDs are registered automatically. A spare bracelet already in the system can be reused.
          </span>
        </label>
        {formError ? <p className="text-sm text-[var(--color-red)]">{formError}</p> : null}
        <Button className="w-full" disabled={create.isPending} onClick={submit}>
          {create.isPending ? 'Registering…' : 'Register user'}
        </Button>
      </div>
    </Modal>
  )
}
