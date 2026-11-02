import { useRef } from 'react'
import { Button } from './ui'

const MAX_BYTES = 5 * 1024 * 1024

export function Avatar({
  name,
  photoUrl,
  size = 'md',
}: {
  name: string
  photoUrl?: string | null
  size?: 'sm' | 'md' | 'lg'
}) {
  const sizes = { sm: 'h-9 w-9 text-xs', md: 'h-11 w-11 text-sm', lg: 'h-20 w-20 text-xl' }
  if (photoUrl) {
    return (
      <img src={photoUrl} alt="" className={`${sizes[size]} shrink-0 rounded-xl object-cover`} />
    )
  }
  const initials =
    name
      .split(' ')
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase())
      .join('') || '?'
  return (
    <div
      className={`${sizes[size]} flex shrink-0 items-center justify-center rounded-xl bg-[var(--color-blue)] font-semibold text-white`}
    >
      {initials}
    </div>
  )
}

export function PhotoUploader({
  name,
  photoUrl,
  busy,
  onUpload,
  onRemove,
  onError,
}: {
  name: string
  photoUrl?: string | null
  busy: boolean
  onUpload: (file: File) => void
  onRemove: () => void
  onError: (message: string) => void
}) {
  const input = useRef<HTMLInputElement>(null)
  return (
    <div className="flex items-center gap-4">
      <Avatar name={name} photoUrl={photoUrl} size="lg" />
      <div className="space-y-2">
        <div className="flex flex-wrap gap-2">
          <Button
            variant="secondary"
            className="px-3 py-1.5 text-xs"
            disabled={busy}
            onClick={() => input.current?.click()}
          >
            {busy ? 'Saving…' : photoUrl ? 'Change picture' : 'Upload picture'}
          </Button>
          {photoUrl ? (
            <Button variant="ghost" className="px-3 py-1.5 text-xs" disabled={busy} onClick={onRemove}>
              Remove
            </Button>
          ) : null}
        </div>
        <p className="text-xs text-slate-500">JPEG, PNG or WebP, up to 5 MB.</p>
      </div>
      <input
        ref={input}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        aria-label="Profile picture"
        className="hidden"
        onChange={(e) => {
          const file = e.target.files?.[0]
          e.target.value = ''
          if (!file) return
          if (file.size > MAX_BYTES) {
            onError('Picture must be 5 MB or smaller.')
            return
          }
          onUpload(file)
        }}
      />
    </div>
  )
}
