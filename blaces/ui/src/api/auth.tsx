import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { authApi } from './services'
import type { Membership, User } from '../types'
import { getErrorMessage } from './client'

interface AuthState {
  user: User | null
  loading: boolean
  activeOrgId: string | null
  login: (identifier: string, password: string, countryCode?: string) => Promise<void>
  completeLogin: (data: {
    user: User
    tokens: { access: string; refresh: string }
  }) => void
  logout: () => void
  refreshUser: () => Promise<void>
  setActiveOrgId: (id: string | null) => void
  activeMembership: Membership | null
}

const AuthContext = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(true)
  const [activeOrgId, setActiveOrgId] = useState<string | null>(
    () => localStorage.getItem('active_org_id'),
  )

  const refreshUser = useCallback(async () => {
    const token = localStorage.getItem('access_token')
    if (!token) {
      setUser(null)
      setLoading(false)
      return
    }
    try {
      const { data } = await authApi.me()
      setUser(data)
      if (!activeOrgId && data.memberships?.length) {
        const id = data.memberships[0].organization_id
        setActiveOrgId(id)
        localStorage.setItem('active_org_id', id)
      }
    } catch {
      setUser(null)
    } finally {
      setLoading(false)
    }
  }, [activeOrgId])

  useEffect(() => {
    void refreshUser()
  }, [refreshUser])

  const completeLogin = (data: {
    user: User
    tokens: { access: string; refresh: string }
  }) => {
    localStorage.setItem('access_token', data.tokens.access)
    localStorage.setItem('refresh_token', data.tokens.refresh)
    setUser(data.user)
    if (data.user.memberships?.length) {
      const id = data.user.memberships[0].organization_id
      setActiveOrgId(id)
      localStorage.setItem('active_org_id', id)
    }
  }

  const login = async (identifier: string, password: string, countryCode?: string) => {
    const { data } = await authApi.login(identifier, password, countryCode)
    completeLogin(data)
  }

  const logout = () => {
    localStorage.removeItem('access_token')
    localStorage.removeItem('refresh_token')
    localStorage.removeItem('active_org_id')
    setUser(null)
    setActiveOrgId(null)
  }

  const setOrg = (id: string | null) => {
    setActiveOrgId(id)
    if (id) localStorage.setItem('active_org_id', id)
    else localStorage.removeItem('active_org_id')
  }

  const activeMembership =
    user?.memberships.find((m) => m.organization_id === activeOrgId) ?? null

  const value = useMemo(
    () => ({
      user,
      loading,
      activeOrgId,
      login,
      completeLogin,
      logout,
      refreshUser,
      setActiveOrgId: setOrg,
      activeMembership,
    }),
    [user, loading, activeOrgId, activeMembership, refreshUser],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth requires AuthProvider')
  return ctx
}

export { getErrorMessage }
