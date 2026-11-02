import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { toast } from 'sonner'
import { getErrorMessage } from '../api/auth'
import { staffApi } from '../api/services'
import { EMPTY_PHONE, isValidEmail, isValidNationalPhone, toE164, type PhoneValue } from '../lib/phone'
import { PhoneInput } from './PhoneInput'
import { Button, ErrorState, Input, LoadingState } from './ui'

const EMPTY_FORM = { first_name: '', last_name: '', email: '' }

/** Super admins invite registrars, who can then register people on the platform. */
export function StaffSection() {
  const qc = useQueryClient()
  const [form, setForm] = useState(EMPTY_FORM)
  const [phone, setPhone] = useState<PhoneValue>(EMPTY_PHONE)
  const [formError, setFormError] = useState('')

  const staff = useQuery({
    queryKey: ['staff'],
    queryFn: async () => (await staffApi.list()).data,
  })

  const refresh = () => void qc.invalidateQueries({ queryKey: ['staff'] })

  const reportSms = (sent: boolean, success: string, username?: string) => {
    if (sent) toast.success(success)
    else {
      toast.warning(
        `We couldn't send the text.${username ? ` Their username is ${username}.` : ''} Ask them to use "Set or reset password" on the sign-in page.`,
        { duration: 10000 },
      )
    }
  }

  const invite = useMutation({
    mutationFn: async () =>
      (
        await staffApi.invite({
          first_name: form.first_name.trim(),
          last_name: form.last_name.trim(),
          phone: toE164(phone),
          email: form.email.trim(),
          country_code: phone.country_code,
        })
      ).data,
    onSuccess: (data) => {
      reportSms(data.sms_sent, `Invitation sent to ${data.full_name}`, data.username)
      setForm(EMPTY_FORM)
      setPhone((p) => ({ ...p, national: '' }))
      refresh()
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const resend = useMutation({
    mutationFn: async (id: string) => (await staffApi.resend(id)).data,
    onSuccess: (data) => reportSms(data.sms_sent, 'Invitation sent again'),
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const removeRole = useMutation({
    mutationFn: (id: string) => staffApi.removeRole(id),
    onSuccess: () => {
      toast.success('Registrar role removed')
      refresh()
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const submit = () => {
    if (!form.first_name.trim()) return setFormError('Enter their first name.')
    if (!isValidNationalPhone(phone.national)) return setFormError('Enter a valid phone number.')
    if (!isValidEmail(form.email)) return setFormError('Enter a valid email, or leave it empty.')
    setFormError('')
    invite.mutate()
  }

  return (
    <div className="admin-card space-y-5 p-5 sm:p-6">
      <div>
        <h2 className="text-base font-semibold text-[var(--color-charcoal)]">Staff</h2>
        <p className="mt-1 text-sm text-slate-500">
          Registrars can register people and give them bracelets, and manage the people they
          registered. They can't delete users, invite staff or change settings.
        </p>
      </div>

      {staff.isLoading ? (
        <LoadingState label="Loading staff…" />
      ) : staff.isError ? (
        <ErrorState message={getErrorMessage(staff.error)} onRetry={() => staff.refetch()} />
      ) : !staff.data?.length ? (
        <p className="text-sm text-slate-500">No registrars yet. Invite your first one below.</p>
      ) : (
        <ul className="divide-y divide-black/[0.04]">
          {staff.data.map((m) => (
            <li key={m.id} className="flex flex-wrap items-center justify-between gap-3 py-3">
              <div className="min-w-0">
                <p className="font-medium text-[var(--color-charcoal)]">
                  {m.full_name}
                  {m.pending ? (
                    <span className="ml-2 rounded-full bg-amber-50 px-2 py-0.5 text-[11px] font-semibold text-amber-700">
                      Invited
                    </span>
                  ) : null}
                </p>
                <p className="text-xs text-slate-500">
                  {[m.username, m.phone, m.email].filter(Boolean).join(' · ')}
                </p>
              </div>
              <div className="flex gap-1.5">
                {m.pending ? (
                  <Button
                    variant="secondary"
                    className="px-2.5 py-1.5 text-xs"
                    disabled={resend.isPending}
                    onClick={() => resend.mutate(m.id)}
                  >
                    Resend invite
                  </Button>
                ) : null}
                <Button
                  variant="ghost"
                  className="px-2.5 py-1.5 text-xs text-[var(--color-red)]"
                  disabled={removeRole.isPending}
                  onClick={() => {
                    if (window.confirm(`Remove ${m.full_name}'s registrar role?`)) {
                      removeRole.mutate(m.id)
                    }
                  }}
                >
                  Remove role
                </Button>
              </div>
            </li>
          ))}
        </ul>
      )}

      <div className="space-y-3 rounded-2xl bg-slate-50/80 p-4">
        <p className="text-sm font-semibold text-[var(--color-charcoal)]">Invite a registrar</p>
        <div className="grid gap-3 sm:grid-cols-2">
          <Input
            placeholder="First name"
            aria-label="First name"
            value={form.first_name}
            onChange={(e) => setForm({ ...form, first_name: e.target.value })}
          />
          <Input
            placeholder="Last name"
            aria-label="Last name"
            value={form.last_name}
            onChange={(e) => setForm({ ...form, last_name: e.target.value })}
          />
        </div>
        <PhoneInput value={phone} onChange={setPhone} />
        <Input
          type="email"
          placeholder="Email (optional)"
          aria-label="Email (optional)"
          value={form.email}
          onChange={(e) => setForm({ ...form, email: e.target.value })}
        />
        {formError ? <p className="text-sm text-[var(--color-red)]">{formError}</p> : null}
        <Button disabled={invite.isPending} onClick={submit}>
          {invite.isPending ? 'Sending…' : 'Send invitation'}
        </Button>
      </div>
    </div>
  )
}
