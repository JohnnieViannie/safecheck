import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { toast } from 'sonner'
import { getErrorMessage } from '../api/auth'
import { contactApi, unwrapList } from '../api/services'
import {
  EMPTY_PHONE,
  RELATIONSHIP_OPTIONS,
  isValidEmail,
  isValidNationalPhone,
  splitPhone,
  toE164,
  type PhoneValue,
} from '../lib/phone'
import type { TrustedContact } from '../types'
import { PhoneInput, useDialCodes } from './PhoneInput'
import { Button, ErrorState, Input, LoadingState, Modal, Select } from './ui'

type Target = { person: string } | { ownerUser: string }

const EMPTY_KIN = { name: '', email: '', relationship: 'Family' as string }

/**
 * A person's next of kin as a simple list, with the form opening only when adding or editing.
 * The backend links a person's contacts to their organization and account, so alerts reach them.
 */
export function NextOfKinPanel({ target }: { target: Target }) {
  const qc = useQueryClient()
  const dialCodes = useDialCodes()
  const filter: Record<string, string> =
    'person' in target ? { person: target.person } : { owner_user: target.ownerUser }
  const [formOpen, setFormOpen] = useState(false)
  const [form, setForm] = useState(EMPTY_KIN)
  const [phone, setPhone] = useState<PhoneValue>(EMPTY_PHONE)
  const [editing, setEditing] = useState<TrustedContact | null>(null)
  const [formError, setFormError] = useState('')

  const contacts = useQuery({
    queryKey: ['next-of-kin', filter],
    queryFn: async () => unwrapList((await contactApi.list({ ...filter, page_size: '50' })).data),
  })

  const closeForm = () => {
    setFormOpen(false)
    setEditing(null)
    setForm(EMPTY_KIN)
    setPhone((p) => ({ ...p, national: '' }))
    setFormError('')
  }

  const save = useMutation({
    mutationFn: async () => {
      const payload = {
        name: form.name.trim(),
        phone: toE164(phone),
        email: form.email.trim(),
        relationship: form.relationship,
        notify_sms: true,
        notify_email: Boolean(form.email.trim()),
        is_active: true,
        ...('person' in target ? { person: target.person } : { owner_user: target.ownerUser }),
      }
      return editing ? contactApi.update(editing.id, payload) : contactApi.create(payload)
    },
    onSuccess: () => {
      toast.success(editing ? 'Next of kin updated' : 'Next of kin added')
      closeForm()
      void qc.invalidateQueries({ queryKey: ['next-of-kin'] })
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const remove = useMutation({
    mutationFn: (id: string) => contactApi.remove(id),
    onSuccess: () => {
      toast.success('Next of kin removed')
      void qc.invalidateQueries({ queryKey: ['next-of-kin'] })
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const submit = () => {
    if (!form.name.trim()) return setFormError('Enter their name.')
    if (!isValidNationalPhone(phone.national)) return setFormError('Enter a valid phone number.')
    if (!isValidEmail(form.email)) return setFormError('Enter a valid email, or leave it empty.')
    setFormError('')
    save.mutate()
  }

  const openAdd = () => {
    closeForm()
    setFormOpen(true)
  }

  const openEdit = (contact: TrustedContact) => {
    const split = splitPhone(contact.phone || '', dialCodes)
    setEditing(contact)
    setFormError('')
    setForm({
      name: contact.name || '',
      email: contact.email || '',
      relationship: contact.relationship || 'Family',
    })
    setPhone({
      country_code: split.country_code,
      dial_code: split.dial_code,
      national: contact.phone ? split.phone_national : '',
    })
    setFormOpen(true)
  }

  return (
    <div className="space-y-3">
      {contacts.isLoading ? (
        <LoadingState label="Loading next of kin…" />
      ) : contacts.isError ? (
        <ErrorState message={getErrorMessage(contacts.error)} onRetry={() => contacts.refetch()} />
      ) : !contacts.data?.length ? (
        <p className="rounded-xl bg-amber-50 px-3 py-2 text-sm font-medium text-amber-700">
          No next of kin yet, so alerts have no one to reach.
        </p>
      ) : (
        <ul className="divide-y divide-black/[0.04] rounded-xl border border-[var(--color-border)]">
          {contacts.data.map((c) => (
            <li key={c.id} className="flex items-center justify-between gap-3 px-3 py-2.5">
              <div className="min-w-0">
                <p className="truncate font-medium text-[var(--color-charcoal)]">{c.name}</p>
                <p className="truncate text-xs text-slate-500">
                  {[c.relationship, c.phone, c.email].filter(Boolean).join(' · ')}
                </p>
              </div>
              <div className="flex shrink-0 gap-1">
                <Button variant="ghost" className="!px-2 !py-1 text-xs" onClick={() => openEdit(c)}>
                  Edit
                </Button>
                <Button
                  variant="ghost"
                  className="!px-2 !py-1 text-xs text-[var(--color-red)]"
                  disabled={remove.isPending}
                  onClick={() => {
                    if (window.confirm(`Remove ${c.name} as next of kin?`)) remove.mutate(c.id)
                  }}
                >
                  Delete
                </Button>
              </div>
            </li>
          ))}
        </ul>
      )}

      <Button variant="secondary" onClick={openAdd}>
        + Add next of kin
      </Button>

      <Modal
        open={formOpen}
        title={editing ? `Edit ${editing.name}` : 'Add next of kin'}
        onClose={closeForm}
      >
        <div className="space-y-3">
          <label className="block space-y-1.5">
            <span className="text-sm font-medium">Name</span>
            <Input
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
            />
          </label>
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
            <span className="text-sm font-medium">Relationship</span>
            <Select
              value={form.relationship}
              onChange={(e) => setForm({ ...form, relationship: e.target.value })}
            >
              {RELATIONSHIP_OPTIONS.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
              {!RELATIONSHIP_OPTIONS.includes(
                form.relationship as (typeof RELATIONSHIP_OPTIONS)[number],
              ) && form.relationship ? (
                <option value={form.relationship}>{form.relationship}</option>
              ) : null}
            </Select>
          </label>
          {formError ? <p className="text-sm text-[var(--color-red)]">{formError}</p> : null}
          <div className="flex gap-2">
            <Button variant="secondary" className="flex-1" onClick={closeForm}>
              Cancel
            </Button>
            <Button className="flex-1" disabled={save.isPending} onClick={submit}>
              {save.isPending ? 'Saving…' : editing ? 'Save changes' : 'Add next of kin'}
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  )
}
