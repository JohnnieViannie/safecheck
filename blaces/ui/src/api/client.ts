import axios, { type AxiosError } from 'axios'

const API_BASE =
  import.meta.env.VITE_API_BASE_URL || 'https://server.safebangle.com/api'

export const api = axios.create({
  baseURL: API_BASE,
  headers: { 'Content-Type': 'application/json' },
})

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('access_token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

let refreshing: Promise<string | null> | null = null

async function refreshAccess(): Promise<string | null> {
  const refresh = localStorage.getItem('refresh_token')
  if (!refresh) return null
  try {
    const { data } = await axios.post(`${API_BASE}/auth/refresh/`, { refresh })
    localStorage.setItem('access_token', data.access)
    if (data.refresh) localStorage.setItem('refresh_token', data.refresh)
    return data.access as string
  } catch {
    localStorage.removeItem('access_token')
    localStorage.removeItem('refresh_token')
    return null
  }
}

api.interceptors.response.use(
  (r) => r,
  async (error: AxiosError) => {
    const original = error.config
    if (error.response?.status === 401 && original && !(original as { _retry?: boolean })._retry) {
      ;(original as { _retry?: boolean })._retry = true
      refreshing = refreshing ?? refreshAccess()
      const token = await refreshing
      refreshing = null
      if (token) {
        original.headers.Authorization = `Bearer ${token}`
        return api(original)
      }
      if (!window.location.pathname.startsWith('/login')) {
        window.location.href = '/login'
      }
    }
    return Promise.reject(error)
  },
)

const FIELD_LABELS: Record<string, string> = {
  email: 'Email',
  identifier: 'Phone or email',
  owner_first_name: 'Owner name',
  owner_phone: 'Owner phone',
  owner_email: 'Owner email',
  password: 'Password',
  first_name: 'First name',
  last_name: 'Last name',
  phone: 'Phone',
  country_code: 'Country',
  sex: 'Sex',
  date_of_birth: 'Date of birth',
  account_type: 'Account type',
  organization_name: 'Organization name',
  code: 'Code',
  non_field_errors: '',
}

function collectMessages(value: unknown, key?: string): string[] {
  if (value == null) return []
  if (typeof value === 'string') {
    const label = key ? FIELD_LABELS[key] ?? key.replace(/_/g, ' ') : ''
    return [label ? `${label}: ${value}` : value]
  }
  if (Array.isArray(value)) {
    return value.flatMap((item) => collectMessages(item, key))
  }
  if (typeof value === 'object') {
    return Object.entries(value as Record<string, unknown>).flatMap(([k, v]) =>
      collectMessages(v, k),
    )
  }
  return [String(value)]
}

export function getErrorMessage(err: unknown): string {
  if (axios.isAxiosError(err)) {
    const data = err.response?.data as {
      error?: string | string[]
      detail?: string
      details?: Record<string, unknown>
      [key: string]: unknown
    }

    if (typeof data?.error === 'string' && data.error !== 'Validation failed') {
      return data.error
    }
    if (Array.isArray(data?.error)) {
      return data.error.map(String).join(' · ')
    }
    if (data?.detail) return String(data.detail)

    if (data?.details && typeof data.details === 'object') {
      const msgs = collectMessages(data.details)
      if (msgs.length) return msgs.join(' · ')
    }

    // Raw DRF field errors without our wrapper
    if (data && typeof data === 'object') {
      const { error: _e, detail: _d, details: _det, ...rest } = data
      const msgs = collectMessages(rest)
      if (msgs.length) return msgs.join(' · ')
    }

    if (typeof data?.error === 'string') return data.error

    if (!err.response) {
      return 'Cannot reach the server. Check that the API is running.'
    }
    return err.message || `Request failed (${err.response.status})`
  }
  if (err instanceof Error) return err.message
  return 'Something went wrong'
}
