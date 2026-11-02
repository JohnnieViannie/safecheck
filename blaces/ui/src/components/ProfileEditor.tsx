import { useMutation } from '@tanstack/react-query'
import { useState } from 'react'
import { toast } from 'sonner'
import { getErrorMessage, useAuth } from '../api/auth'
import { authApi } from '../api/services'
import { PhotoUploader } from './PhotoUploader'
import { useDialCodes } from './PhoneInput'
import { Button, Input, Select } from './ui'

/** The signed-in person's own details, address and picture. */
export function ProfileEditor() {
  const { user, refreshUser } = useAuth()
  const dialCodes = useDialCodes()
  const [form, setForm] = useState({
    first_name: user?.first_name || '',
    last_name: user?.last_name || '',
    phone: user?.phone || '',
    date_of_birth: user?.date_of_birth || '',
    city: user?.city || '',
    country_code: user?.country_code || '',
    address: user?.address || '',
  })

  const save = useMutation({
    mutationFn: () => authApi.updateMe({ ...form, date_of_birth: form.date_of_birth || null }),
    onSuccess: async () => {
      await refreshUser()
      toast.success('Profile updated')
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  const photo = useMutation({
    mutationFn: (file: File | null) =>
      file ? authApi.uploadMyPhoto(file) : authApi.removeMyPhoto(),
    onSuccess: async () => {
      await refreshUser()
      toast.success('Picture updated')
    },
    onError: (e) => toast.error(getErrorMessage(e)),
  })

  return (
    <div className="space-y-4">
      <PhotoUploader
        name={user?.full_name || ''}
        photoUrl={user?.photo_url}
        busy={photo.isPending}
        onUpload={(file) => photo.mutate(file)}
        onRemove={() => photo.mutate(null)}
        onError={(message) => toast.error(message)}
      />
      <dl className="grid gap-3 rounded-2xl bg-slate-50/80 p-3 text-sm sm:grid-cols-2">
        <div>
          <dt className="text-xs text-slate-400">Username</dt>
          <dd className="font-mono font-medium text-[var(--color-charcoal)]">{user?.username}</dd>
        </div>
        <div>
          <dt className="text-xs text-slate-400">Email</dt>
          <dd className="text-[var(--color-charcoal)]">{user?.email || 'Not added'}</dd>
        </div>
      </dl>
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
      <label className="block space-y-1.5">
        <span className="text-sm font-medium">Phone</span>
        <Input
          inputMode="tel"
          value={form.phone}
          onChange={(e) => setForm({ ...form, phone: e.target.value })}
        />
      </label>
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
      <Button disabled={save.isPending} onClick={() => save.mutate()}>
        {save.isPending ? 'Saving…' : 'Save profile'}
      </Button>
    </div>
  )
}
