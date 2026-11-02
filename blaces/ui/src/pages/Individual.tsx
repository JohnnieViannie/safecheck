import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { toast } from 'sonner'
import { getErrorMessage, useAuth } from '../api/auth'
import {
  alertApi,
  authApi,
  braceletApi,
  contactApi,
  dashboardApi,
  peopleApi,
  unwrapList,
} from '../api/services'
import {
  Button,
  EmptyState,
  ErrorState,
  Input,
  LoadingState,
  Modal,
  PageHeader,
  Select,
  StatCard,
  StatusBadge,
} from '../components/ui'
import { ProfileEditor } from '../components/ProfileEditor'
import { AlertsPage } from './org/Alerts'
import { IncidentsPage } from './org/Incidents'
import {
  FALLBACK_DIAL_CODES,
  RELATIONSHIP_OPTIONS,
  isValidEmail,
  isValidNationalPhone,
  nationalPhoneDigits,
  splitPhone,
  type DialCode,
} from '../lib/phone'
import type { TrustedContact } from '../types'

const EMPTY_FORM = {
  name: '',
  country_code: 'UG',
  dial_code: '+256',
  phone_national: '',
  email: '',
  relationship: 'Family' as string,
}

function formatAlertTime(value?: string | null) {
  if (!value) return ''
  try {
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(value))
  } catch {
    return value
  }
}

export function IndividualDashboard() {
  const { user } = useAuth()
  const summary = useQuery({
    queryKey: ['ind-dashboard'],
    queryFn: async () => (await dashboardApi.summary()).data,
    refetchInterval: 5000,
  })
  const alerts = useQuery({
    queryKey: ['ind-alerts'],
    queryFn: async () =>
      unwrapList((await alertApi.list({ ordering: '-received_at', page_size: '5' })).data),
    refetchInterval: 5000,
  })
  const contacts = useQuery({
    queryKey: ['my-contacts'],
    queryFn: async () => unwrapList((await contactApi.list()).data),
  })

  if (summary.isLoading) return <LoadingState />
  if (summary.isError) return <ErrorState message={getErrorMessage(summary.error)} />

  const s = summary.data!
  const firstName = user?.first_name?.trim() || user?.full_name?.split(' ')[0] || 'there'
  const braceletCount = s.bracelets.total
  const openIncidents = s.incidents.open
  const hasBracelet = braceletCount > 0
  const needsAttention = openIncidents > 0
  const contactCount = contacts.data?.length ?? 0

  const statusLabel = needsAttention
    ? 'Attention needed'
    : hasBracelet
      ? 'Coverage active'
      : 'Setup required'
  const statusCopy = needsAttention
    ? `${openIncidents} open incident${openIncidents === 1 ? '' : 's'} need your review.`
    : hasBracelet
      ? 'Your bracelet is linked. Alerts will appear here the moment they arrive.'
      : 'Register your SafeBangle to start live monitoring and trusted-contact alerts.'
  const pulseClass = needsAttention
    ? 'bg-[#ffb4b7]'
    : hasBracelet
      ? 'bg-emerald-300'
      : 'bg-amber-300'

  return (
    <div className="dash-enter mx-auto max-w-5xl space-y-5 sm:space-y-6">
      <PageHeader
        title={`Welcome back, ${firstName}`}
        subtitle={statusCopy}
        actions={
          <>
            <Link
              to="/me/bracelet"
              className="inline-flex h-11 w-full items-center justify-center rounded-xl bg-[var(--color-blue)] px-4 text-sm font-semibold text-white hover:bg-[var(--color-blue-dark)] sm:w-auto"
            >
              My bracelet
            </Link>
            <Link
              to="/me/contacts"
              className="inline-flex h-11 w-full items-center justify-center rounded-xl border border-[var(--color-border)] bg-white px-4 text-sm font-semibold text-[var(--color-charcoal)] hover:bg-slate-50 sm:w-auto"
            >
              Trusted contacts
            </Link>
          </>
        }
      />

      <div className="inline-flex items-center gap-2 rounded-xl bg-white px-3 py-1.5 text-xs font-semibold text-slate-600 shadow-sm ring-1 ring-[var(--color-border)]">
        <span className={`dash-pulse ${pulseClass}`} aria-hidden />
        {statusLabel}
      </div>

      <section className="dash-enter-delay-1 grid grid-cols-1 gap-3 sm:grid-cols-3">
        <Link to="/me/bracelet" className="block">
          <StatCard
            featured
            label="Bracelets"
            value={braceletCount}
            hint={hasBracelet ? 'Linked to your account' : 'None registered yet'}
          />
        </Link>
        <Link to="/me/incidents" className="block">
          <StatCard
            label="Open incidents"
            value={openIncidents}
            tone={needsAttention ? 'danger' : 'default'}
            hint={needsAttention ? 'Needs follow-up' : 'All clear'}
          />
        </Link>
        <Link to="/me/contacts" className="block">
          <StatCard
            label="Trusted contacts"
            value={contactCount}
            hint={contactCount ? 'Ready for alerts' : 'Add people who can help'}
          />
        </Link>
      </section>

      <section className="dash-enter-delay-2 console-card overflow-hidden">
        <div className="flex flex-col gap-2 px-5 py-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 className="text-base font-semibold text-[var(--color-charcoal)]">Recent alerts</h2>
            <p className="text-sm text-slate-500">Live stream from your SafeBangle</p>
          </div>
          <Link
            to="/me/alerts"
            className="rounded-xl bg-slate-50 px-3 py-1.5 text-sm font-semibold text-[var(--color-blue)] hover:bg-slate-100"
          >
            View all
          </Link>
        </div>

        {alerts.isLoading ? (
          <LoadingState label="Loading alerts…" />
        ) : alerts.data?.length ? (
          <ul className="space-y-0 px-5 pb-4">
            {alerts.data.map((a) => (
              <li key={a.id} className="dash-timeline-item py-3">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="text-sm font-semibold text-[var(--color-charcoal)]">
                      {a.alert_code}
                      <span className="font-normal text-slate-400"> · {a.device_id}</span>
                    </p>
                    <p className="mt-1 text-xs text-slate-500">{formatAlertTime(a.received_at)}</p>
                  </div>
                  <StatusBadge status={a.alert_code} />
                </div>
              </li>
            ))}
          </ul>
        ) : (
          <div className="px-5 pb-10 pt-4 text-center">
            <p className="font-display text-lg text-[var(--color-charcoal)]">Quiet for now</p>
            <p className="mx-auto mt-2 max-w-sm text-sm leading-relaxed text-slate-500">
              {hasBracelet
                ? 'No alerts yet. When your bracelet signals, the event will land here instantly.'
                : 'Once your bracelet is on your account, emergency signals will stream into this feed.'}
            </p>
            {!hasBracelet ? (
              <Link
                to="/me/bracelet"
                className="mt-5 inline-flex h-10 items-center rounded-xl bg-[var(--color-blue)] px-4 text-sm font-semibold text-white hover:bg-[var(--color-blue-dark)]"
              >
                My bracelet
              </Link>
            ) : null}
          </div>
        )}
      </section>

      {!hasBracelet || !contactCount ? (
        <section className="dash-enter-delay-3 grid gap-3 md:grid-cols-2">
          {!hasBracelet ? (
            <Link
              to="/me/bracelet"
              className="console-card border-dashed px-5 py-5 transition hover:border-[var(--color-blue)]/30"
            >
              <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-[var(--color-blue)]">
                Step 1
              </p>
              <p className="mt-2 text-lg font-semibold text-[var(--color-charcoal)]">
                Link your bracelet
              </p>
              <p className="mt-1 text-sm text-slate-500">
                Enter the device ID from your SafeBangle packaging.
              </p>
            </Link>
          ) : null}
          {!contactCount ? (
            <Link
              to="/me/contacts"
              className="console-card border-dashed px-5 py-5 transition hover:border-slate-300"
            >
              <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-slate-400">
                {hasBracelet ? 'Next' : 'Step 2'}
              </p>
              <p className="mt-2 text-lg font-semibold text-[var(--color-charcoal)]">
                Add trusted contacts
              </p>
              <p className="mt-1 text-sm text-slate-500">
                People who should be notified when an alert fires.
              </p>
            </Link>
          ) : null}
        </section>
      ) : null}
    </div>
  )
}

export function MyBraceletPage() {
  const bracelets = useQuery({
    queryKey: ['my-bracelets'],
    queryFn: async () => unwrapList((await braceletApi.list()).data),
  })

  if (bracelets.isLoading) return <LoadingState />
  return (
    <div>
      <PageHeader title="My bracelet" />
      {!bracelets.data?.length ? (
        <EmptyState
          title="No bracelet on your account"
          description="SafeBangle registers your bracelet for you. Please contact us if yours is missing."
        />
      ) : (
        <div className="space-y-3">
          {bracelets.data.map((b) => (
            <div key={b.id} className="rounded-lg border border-[var(--color-border)] bg-white p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-lg font-semibold">{b.device_id}</p>
                  <p className="text-sm text-slate-500">Serial: {b.serial_number || '—'}</p>
                </div>
                <StatusBadge status={b.status} />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

export function MyContactsPage() {
  const qc = useQueryClient()
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<TrustedContact | null>(null)
  const [formError, setFormError] = useState<string | null>(null)
  const [dialCodes, setDialCodes] = useState<DialCode[]>(FALLBACK_DIAL_CODES)
  const [form, setForm] = useState(EMPTY_FORM)

  useEffect(() => {
    if (!open) return
    let cancelled = false
    authApi
      .geo()
      .then(({ data }) => {
        if (cancelled) return
        const codes = data.dial_codes?.length ? data.dial_codes : FALLBACK_DIAL_CODES
        setDialCodes(codes)
        // Only auto-detect country when adding a new contact.
        if (!editing) {
          setForm((f) => ({
            ...f,
            country_code: data.country_code || f.country_code,
            dial_code: data.dial_code || f.dial_code,
          }))
        }
      })
      .catch(() => {
        /* keep fallback dial codes */
      })
    return () => {
      cancelled = true
    }
  }, [open, editing])

  const query = useQuery({
    queryKey: ['my-contacts'],
    queryFn: async () => unwrapList((await contactApi.list()).data),
  })

  const fullPhone = useMemo(() => {
    const national = nationalPhoneDigits(form.phone_national)
    if (!national || !form.dial_code) return ''
    return `${form.dial_code}${national}`
  }, [form.dial_code, form.phone_national])

  const resetForm = () => {
    setForm(EMPTY_FORM)
    setFormError(null)
    setEditing(null)
  }

  const openCreate = () => {
    resetForm()
    setOpen(true)
  }

  const openEdit = (contact: TrustedContact) => {
    const codes = dialCodes.length ? dialCodes : FALLBACK_DIAL_CODES
    const parsed = splitPhone(contact.phone || '', codes)
    const relationship = RELATIONSHIP_OPTIONS.includes(
      contact.relationship as (typeof RELATIONSHIP_OPTIONS)[number],
    )
      ? contact.relationship
      : contact.relationship || 'Family'
    setEditing(contact)
    setFormError(null)
    setForm({
      name: contact.name || '',
      country_code: parsed.country_code,
      dial_code: parsed.dial_code,
      phone_national: parsed.phone_national,
      email: contact.email || '',
      relationship,
    })
    setOpen(true)
  }

  const saveMutation = useMutation({
    mutationFn: async () => {
      const payload = {
        name: form.name.trim(),
        phone: fullPhone,
        email: form.email.trim(),
        relationship: form.relationship,
        notify_sms: true,
        notify_email: Boolean(form.email.trim()),
      }
      if (editing) {
        return contactApi.update(editing.id, payload)
      }
      return contactApi.create(payload)
    },
    onSuccess: () => {
      toast.success(editing ? 'Contact updated' : 'Contact added')
      setOpen(false)
      resetForm()
      void qc.invalidateQueries({ queryKey: ['my-contacts'] })
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const removeMutation = useMutation({
    mutationFn: (id: string) => contactApi.remove(id),
    onSuccess: () => {
      toast.success('Contact deleted')
      void qc.invalidateQueries({ queryKey: ['my-contacts'] })
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const validateAndSave = () => {
    if (!form.name.trim()) {
      setFormError('Name is required')
      return
    }
    if (!form.country_code || !form.dial_code) {
      setFormError('Select a country / dial code')
      return
    }
    if (!form.phone_national.trim()) {
      setFormError('Phone number is required')
      return
    }
    if (!isValidNationalPhone(form.phone_national)) {
      setFormError('Enter a valid phone number (7–12 digits, without the country code)')
      return
    }
    if (!isValidEmail(form.email)) {
      setFormError('Enter a valid email address')
      return
    }
    if (!form.relationship) {
      setFormError('Select a relationship')
      return
    }
    setFormError(null)
    saveMutation.mutate()
  }

  const confirmDelete = (contact: TrustedContact) => {
    if (
      !window.confirm(
        `Delete trusted contact “${contact.name}”? They will no longer receive SOS alerts.`,
      )
    ) {
      return
    }
    removeMutation.mutate(contact.id)
  }

  if (query.isLoading) return <LoadingState />
  return (
    <div>
      <PageHeader
        title="Trusted contacts"
        actions={<Button onClick={openCreate}>Add contact</Button>}
      />
      {!query.data?.length ? (
        <EmptyState title="No trusted contacts" actionLabel="Add contact" onAction={openCreate} />
      ) : (
        <ul className="divide-y rounded-lg border border-[var(--color-border)] bg-white">
          {query.data.map((c) => (
            <li
              key={c.id}
              className="flex flex-col gap-3 px-4 py-3 text-sm sm:flex-row sm:items-center sm:justify-between"
            >
              <div className="min-w-0">
                <p className="font-medium text-[var(--color-charcoal)]">{c.name}</p>
                <p className="truncate text-slate-500">
                  {c.phone}
                  {c.email ? ` · ${c.email}` : ''}
                </p>
                <p className="mt-0.5 text-xs text-slate-400">{c.relationship || '—'}</p>
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <Button variant="secondary" className="px-3 py-2" onClick={() => openEdit(c)}>
                  Edit
                </Button>
                <Button
                  variant="danger"
                  className="px-3 py-2"
                  disabled={removeMutation.isPending}
                  onClick={() => confirmDelete(c)}
                >
                  Delete
                </Button>
              </div>
            </li>
          ))}
        </ul>
      )}
      <Modal
        open={open}
        title={editing ? 'Edit trusted contact' : 'Add trusted contact'}
        onClose={() => {
          setOpen(false)
          resetForm()
        }}
      >
        <div className="space-y-3">
          <label className="block space-y-1.5">
            <span className="text-sm font-medium text-[var(--color-charcoal)]">Name</span>
            <Input
              placeholder="Full name"
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              autoComplete="name"
            />
          </label>

          <label className="block space-y-1.5">
            <span className="text-sm font-medium text-[var(--color-charcoal)]">Phone</span>
            <div className="flex gap-2">
              <Select
                className="max-w-[11.5rem] shrink-0"
                value={form.country_code}
                onChange={(e) => {
                  const iso = e.target.value
                  const match = dialCodes.find((c) => c.iso2 === iso)
                  setForm({
                    ...form,
                    country_code: iso,
                    dial_code: match?.dial_code || form.dial_code,
                  })
                }}
              >
                {dialCodes.map((c) => (
                  <option key={c.iso2} value={c.iso2}>
                    {c.iso2} ({c.dial_code})
                  </option>
                ))}
              </Select>
              <Input
                className="flex-1"
                placeholder="779 697 569"
                inputMode="tel"
                value={form.phone_national}
                onChange={(e) => setForm({ ...form, phone_national: e.target.value })}
                autoComplete="tel-national"
              />
            </div>
            <span className="block text-xs text-slate-400">
              Saved as {fullPhone || `${form.dial_code}…`} — enter the number without the country
              code (leading 0 is removed).
            </span>
          </label>

          <label className="block space-y-1.5">
            <span className="text-sm font-medium text-[var(--color-charcoal)]">Email (optional)</span>
            <Input
              type="email"
              placeholder="email@example.com"
              value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
              autoComplete="email"
            />
          </label>

          <label className="block space-y-1.5">
            <span className="text-sm font-medium text-[var(--color-charcoal)]">Relationship</span>
            <Select
              value={form.relationship}
              onChange={(e) => setForm({ ...form, relationship: e.target.value })}
            >
              {!RELATIONSHIP_OPTIONS.includes(
                form.relationship as (typeof RELATIONSHIP_OPTIONS)[number],
              ) && form.relationship ? (
                <option value={form.relationship}>{form.relationship}</option>
              ) : null}
              {RELATIONSHIP_OPTIONS.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </Select>
          </label>

          {formError ? (
            <p className="rounded-xl bg-[var(--color-red-soft)] px-3 py-2 text-sm text-[var(--color-red)]">
              {formError}
            </p>
          ) : null}

          <Button
            className="w-full"
            onClick={validateAndSave}
            disabled={saveMutation.isPending || !form.name.trim()}
          >
            {saveMutation.isPending ? 'Saving…' : editing ? 'Save changes' : 'Save'}
          </Button>
        </div>
      </Modal>
    </div>
  )
}

export function ProfilePage() {
  return (
    <div>
      <PageHeader title="My profile" subtitle="Your details, address and picture" />
      <div className="max-w-2xl rounded-lg border border-[var(--color-border)] bg-white p-4 sm:p-5">
        <ProfileEditor />
      </div>
    </div>
  )
}

export function MyAlertsPage() {
  return <AlertsPage scoped={false} />
}
export function MyIncidentsPage() {
  return <IncidentsPage scoped={false} />
}
