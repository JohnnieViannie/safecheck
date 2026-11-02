import { useQuery } from '@tanstack/react-query'
import { useEffect, useRef } from 'react'
import { authApi } from '../api/services'
import { FALLBACK_DIAL_CODES, type PhoneValue } from '../lib/phone'
import { Input, Select } from './ui'

export function useGeo() {
  return useQuery({
    queryKey: ['geo'],
    queryFn: async () => (await authApi.geo()).data,
    staleTime: 60 * 60 * 1000,
    retry: false,
  })
}

export function useDialCodes() {
  const geo = useGeo()
  return geo.data?.dial_codes?.length ? geo.data.dial_codes : FALLBACK_DIAL_CODES
}

/** Dial code picker and number. Starts on the visitor's detected country. */
export function PhoneInput({
  value,
  onChange,
  placeholder = '712 345 678',
}: {
  value: PhoneValue
  onChange: (value: PhoneValue) => void
  placeholder?: string
}) {
  const geo = useGeo()
  const dialCodes = useDialCodes()
  const detected = useRef(false)

  useEffect(() => {
    if (detected.current || !geo.data?.dial_code || value.national) return
    detected.current = true
    onChange({
      ...value,
      country_code: geo.data.country_code || value.country_code,
      dial_code: geo.data.dial_code,
    })
    // Only the first geo result sets the default; later edits belong to the person typing.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [geo.data])

  return (
    <div className="flex gap-2">
      <Select
        className="max-w-[9.5rem] shrink-0"
        aria-label="Country code"
        value={value.country_code}
        onChange={(e) => {
          const match = dialCodes.find((c) => c.iso2 === e.target.value)
          onChange({
            ...value,
            country_code: e.target.value,
            dial_code: match?.dial_code || value.dial_code,
          })
        }}
      >
        {dialCodes.map((c) => (
          <option key={c.iso2} value={c.iso2}>
            {c.name} ({c.dial_code})
          </option>
        ))}
      </Select>
      <Input
        className="min-w-0 flex-1"
        inputMode="tel"
        aria-label="Phone number"
        placeholder={placeholder}
        value={value.national}
        onChange={(e) => onChange({ ...value, national: e.target.value })}
      />
    </div>
  )
}
