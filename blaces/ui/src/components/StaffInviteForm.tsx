import { useMutation, useQueryClient } from '@tanstack/react-query'
import axios from 'axios'
import { useState } from 'react'
import { toast } from 'sonner'
import { getErrorMessage } from '../api/auth'
import { orgApi } from '../api/services'
import { EMPTY_PHONE, isValidEmail, isValidNationalPhone, toE164, type PhoneValue } from '../lib/phone'
import { PhoneInput } from './PhoneInput'
import { Button, Input, Select } from './ui'

/**
 * Add dashboard staff by phone or email. Someone new gets an account straight away. Someone with
 * an account gets an invitation to accept, or joins directly when `addExisting` is set.
 */
export function StaffInviteForm({
  organizationId,
  addExisting = false,
}: {
  organizationId: string
  addExisting?: boolean
}) {
  const qc = useQueryClient()
  const [phone, setPhone] = useState<PhoneValue>(EMPTY_PHONE)
  const [firstName, setFirstName] = useState('')
  const [email, setEmail] = useState('')
  const [role, setRole] = useState('STAFF')
  const [formError, setFormError] = useState('')

  const send = useMutation({
    mutationFn: async (): Promise<'added' | 'invited' | 'joined'> => {
      const phoneValue = toE164(phone)
      const emailValue = email.trim()
      if (addExisting) {
        try {
          await orgApi.addMember(organizationId, {
            identifier: phoneValue || emailValue,
            role,
          })
          return 'added'
        } catch (err) {
          if (!axios.isAxiosError(err) || err.response?.status !== 404) throw err
        }
      }
      const { data } = await orgApi.invite(organizationId, {
        first_name: firstName.trim(),
        phone: phoneValue,
        email: emailValue,
        role,
      })
      return 'joined' in data ? 'joined' : 'invited'
    },
    onSuccess: (result) => {
      const messages = {
        added: 'Staff member added',
        invited: 'Invitation sent',
        joined: 'Staff member added. We sent them how to set a password.',
      }
      toast.success(messages[result])
      setPhone((p) => ({ ...p, national: '' }))
      setFirstName('')
      setEmail('')
      void qc.invalidateQueries({ queryKey: ['org-members', organizationId] })
      void qc.invalidateQueries({ queryKey: ['org-invites', organizationId] })
      void qc.invalidateQueries({ queryKey: ['admin-orgs'] })
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const submit = () => {
    if (!phone.national.trim() && !email.trim()) return setFormError('Enter a phone number or email.')
    if (phone.national.trim() && !isValidNationalPhone(phone.national)) {
      return setFormError('Enter a valid phone number.')
    }
    if (!isValidEmail(email)) return setFormError('Enter a valid email, or leave it empty.')
    setFormError('')
    send.mutate()
  }

  return (
    <div className="space-y-2">
      <Input
        placeholder="First name"
        aria-label="First name"
        value={firstName}
        onChange={(e) => setFirstName(e.target.value)}
      />
      <PhoneInput value={phone} onChange={setPhone} />
      <Input
        type="email"
        placeholder="Email (optional)"
        aria-label="Email (optional)"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
      />
      <Select aria-label="Role" value={role} onChange={(e) => setRole(e.target.value)}>
        {['ADMIN', 'STAFF', 'RESPONDER', 'VIEWER'].map((r) => (
          <option key={r} value={r}>
            {r}
          </option>
        ))}
      </Select>
      {formError ? <p className="text-sm text-[var(--color-red)]">{formError}</p> : null}
      <Button className="w-full" disabled={send.isPending} onClick={submit}>
        {send.isPending ? 'Sending…' : addExisting ? 'Add staff member' : 'Send invitation'}
      </Button>
    </div>
  )
}
