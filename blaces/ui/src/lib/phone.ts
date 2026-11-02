export const RELATIONSHIP_OPTIONS = [
  'Family',
  'Colleague',
  'Friend',
  'Supervisor',
  'Police',
] as const

export const FALLBACK_DIAL_CODES = [
  { iso2: 'UG', name: 'Uganda', dial_code: '+256' },
  { iso2: 'KE', name: 'Kenya', dial_code: '+254' },
  { iso2: 'TZ', name: 'Tanzania', dial_code: '+255' },
  { iso2: 'RW', name: 'Rwanda', dial_code: '+250' },
  { iso2: 'US', name: 'United States', dial_code: '+1' },
  { iso2: 'GB', name: 'United Kingdom', dial_code: '+44' },
]

export type DialCode = { iso2: string; name: string; dial_code: string }

export type PhoneValue = { country_code: string; dial_code: string; national: string }

export const EMPTY_PHONE: PhoneValue = { country_code: 'UG', dial_code: '+256', national: '' }

export function isValidEmail(value: string) {
  if (!value.trim()) return true
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim())
}

export function nationalPhoneDigits(value: string) {
  return value.replace(/\D/g, '').replace(/^0+/, '')
}

export function isValidNationalPhone(value: string) {
  const digits = nationalPhoneDigits(value)
  return digits.length >= 7 && digits.length <= 12
}

export function toE164(value: PhoneValue) {
  const digits = nationalPhoneDigits(value.national)
  return digits ? `${value.dial_code}${digits}` : ''
}

export function splitPhone(
  phone: string,
  dialCodes: DialCode[],
): { country_code: string; dial_code: string; phone_national: string } {
  const normalized = phone.trim().replace(/\s+/g, '')
  const withPlus = normalized.startsWith('+') ? normalized : `+${normalized.replace(/\D/g, '')}`
  const sorted = [...dialCodes].sort((a, b) => b.dial_code.length - a.dial_code.length)
  for (const code of sorted) {
    if (withPlus.startsWith(code.dial_code)) {
      return {
        country_code: code.iso2,
        dial_code: code.dial_code,
        phone_national: withPlus.slice(code.dial_code.length),
      }
    }
  }
  return {
    country_code: 'UG',
    dial_code: '+256',
    phone_national: withPlus.replace(/^\+/, ''),
  }
}
