import { useEffect, useState, type ComponentType } from 'react'
import {
  Activity,
  AlertTriangle,
  Building2,
  ClipboardList,
  LayoutDashboard,
  LogOut,
  Menu,
  Settings,
  Shield,
  Users,
  Watch,
  X,
  UserRound,
  Contact,
  FileText,
  MessageSquare,
  ScrollText,
} from 'lucide-react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../api/auth'
import { Avatar } from '../components/PhotoUploader'
import { Select } from '../components/ui'

type NavItemDef = { to: string; label: string; icon: ComponentType<{ className?: string }> }

function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <div className="flex min-w-0 items-center gap-2.5">
      <img
        src="/logo.png"
        alt=""
        className={`${compact ? 'h-8 w-8' : 'h-9 w-9'} shrink-0 rounded-xl object-cover ring-1 ring-black/5`}
      />
      <div className={`font-display tracking-tight ${compact ? 'text-lg' : 'text-xl'}`}>
        <span className="brand-safe">Safe</span>
        <span className="brand-bangle">Bangle</span>
      </div>
    </div>
  )
}

function NavItem({
  to,
  label,
  icon: Icon,
  onNavigate,
  soft,
}: {
  to: string
  label: string
  icon: ComponentType<{ className?: string }>
  onNavigate?: () => void
  soft?: boolean
}) {
  return (
    <NavLink
      to={to}
      end={to.endsWith('/me') || to.endsWith('/app') || to.endsWith('/admin')}
      onClick={onNavigate}
      className={({ isActive }) =>
        soft
          ? `console-nav-item flex items-center gap-3 rounded-2xl px-3 py-2.5 text-sm font-medium ${
              isActive
                ? 'admin-nav-active'
                : 'text-slate-600 hover:bg-slate-50 hover:text-[var(--color-charcoal)]'
            }`
          : `console-nav-item flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium ${
              isActive
                ? 'bg-[var(--color-blue)] text-white shadow-[0_10px_24px_-12px_rgba(8,74,130,0.7)]'
                : 'text-slate-600 hover:bg-slate-50 hover:text-[var(--color-charcoal)]'
            }`
      }
    >
      {({ isActive }) => (
        <>
          <Icon
            className={`h-4 w-4 shrink-0 ${
              isActive
                ? soft
                  ? 'text-[var(--color-blue)]'
                  : 'text-white'
                : 'text-slate-400'
            }`}
          />
          <span className="truncate">{label}</span>
        </>
      )}
    </NavLink>
  )
}

export function AppShell({
  nav,
  base,
  mode,
}: {
  nav: NavItemDef[]
  base: string
  mode: 'organization' | 'individual' | 'admin'
}) {
  const { user, logout, activeOrgId, setActiveOrgId, activeMembership } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [menuOpen, setMenuOpen] = useState(false)
  const isAdmin = mode === 'admin'
  const staffLabel = user?.is_platform_admin ? 'Platform admin' : 'Registrar'

  useEffect(() => {
    setMenuOpen(false)
  }, [location.pathname])

  useEffect(() => {
    if (!menuOpen) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setMenuOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [menuOpen])

  const accountBadge =
    mode === 'admin'
      ? staffLabel
      : mode === 'organization'
        ? 'Organization'
        : 'Individual'

  const closeMenu = () => setMenuOpen(false)

  const renderNav = () => (
    <nav className="min-h-0 flex-1 space-y-1 overflow-y-auto overscroll-contain px-3 py-4">
      <p className="mb-2 px-3 text-[11px] font-semibold uppercase tracking-[0.14em] text-slate-400">
        Menu
      </p>
      {nav.map((item) => (
        <NavItem
          key={item.to}
          to={`${base}${item.to}`}
          label={item.label}
          icon={item.icon}
          onNavigate={closeMenu}
          soft={isAdmin}
        />
      ))}
    </nav>
  )

  const renderFooter = () => (
    <div className="shrink-0 space-y-3 border-t border-[var(--color-border)] p-4">
      {isAdmin ? (
        <div className="admin-wave relative overflow-hidden px-4 py-4">
          <div className="relative z-10">
            <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-blue-100/85">
              {accountBadge}
            </p>
            <p className="mt-1 truncate text-sm font-semibold text-white">Platform console</p>
            <p className="mt-1 text-xs text-blue-100/80">Orgs, users & device coverage</p>
          </div>
        </div>
      ) : (
        <div className="rounded-2xl bg-[var(--color-blue)] px-4 py-4 text-white shadow-[0_14px_28px_-16px_rgba(8,74,130,0.7)]">
          <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-blue-100">
            {accountBadge}
          </p>
          <p className="mt-1 truncate text-sm font-semibold">
            {mode === 'organization'
              ? activeMembership?.organization_name || 'Organization'
              : 'Personal safety'}
          </p>
          <p className="mt-1 text-xs text-blue-100/85">
            {mode === 'organization'
              ? 'People, bracelets & response'
              : 'Device, alerts & contacts'}
          </p>
        </div>
      )}
      <button
        type="button"
        className="flex w-full items-center gap-2 rounded-xl px-3 py-2.5 text-sm font-medium text-slate-600 hover:bg-slate-50"
        onClick={() => {
          logout()
          navigate('/login')
        }}
      >
        <LogOut className="h-4 w-4 text-slate-400" />
        Sign out
      </button>
    </div>
  )

  return (
    <div
      className={`console-shell relative flex h-dvh max-h-dvh overflow-hidden ${isAdmin ? 'admin-shell' : ''}`}
    >
      <aside
        className={`console-sidebar relative hidden h-full w-[17rem] shrink-0 flex-col overflow-hidden lg:flex ${
          isAdmin ? 'admin-sidebar' : ''
        }`}
      >
        <div className="shrink-0 px-5 py-5">
          <Brand />
        </div>
        {renderNav()}
        {renderFooter()}
      </aside>

      <div
        className={`fixed inset-0 z-40 lg:hidden ${menuOpen ? 'pointer-events-auto' : 'pointer-events-none'}`}
      >
        <button
          type="button"
          aria-label="Close menu"
          className={`absolute inset-0 bg-black/40 transition-opacity ${
            menuOpen ? 'opacity-100' : 'opacity-0'
          }`}
          onClick={closeMenu}
        />
        <aside
          className={`console-sidebar absolute inset-y-0 left-0 flex w-[min(18rem,88vw)] max-w-full flex-col overflow-hidden shadow-2xl transition-transform duration-200 ease-out ${
            isAdmin ? 'admin-sidebar' : ''
          } ${menuOpen ? 'translate-x-0' : '-translate-x-full'}`}
        >
          <div className="flex shrink-0 items-center justify-between gap-3 px-4 py-3">
            <Brand compact />
            <button
              type="button"
              className="rounded-xl p-2 text-slate-500 hover:bg-slate-50"
              onClick={closeMenu}
              aria-label="Close navigation"
            >
              <X className="h-5 w-5" />
            </button>
          </div>
          {renderNav()}
          {renderFooter()}
        </aside>
      </div>

      <div className="console-main-wash flex h-full min-h-0 min-w-0 flex-1 flex-col overflow-hidden">
        <header className="flex shrink-0 items-center gap-3 px-3 py-3 sm:gap-4 sm:px-6 sm:py-4">
          <button
            type="button"
            className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-[var(--color-border)] bg-white text-[var(--color-charcoal)] shadow-sm lg:hidden"
            onClick={() => setMenuOpen(true)}
            aria-label="Open navigation"
            aria-expanded={menuOpen}
          >
            <Menu className="h-5 w-5" />
          </button>

          <div className="hidden min-w-0 flex-1 md:block">
            <div className="flex h-11 max-w-xl items-center rounded-2xl border border-[var(--color-border)] bg-white px-4 text-sm text-slate-400 shadow-sm">
              {isAdmin ? 'Search platform…' : 'Search console…'}
            </div>
          </div>

          <div className="ml-auto flex min-w-0 items-center gap-2 sm:gap-3">
            {mode === 'organization' && user && user.memberships.length > 1 ? (
              <Select
                value={activeOrgId ?? ''}
                onChange={(e) => setActiveOrgId(e.target.value || null)}
                className="max-w-[40vw] shrink-0 sm:max-w-xs"
              >
                {user.memberships.map((m) => (
                  <option key={m.organization_id} value={m.organization_id}>
                    {m.organization_name}
                  </option>
                ))}
              </Select>
            ) : null}

            {isAdmin ? (
              <div className="hidden items-center rounded-2xl border border-[var(--color-border)] bg-white px-3 py-2 text-xs font-semibold text-[var(--color-blue)] shadow-sm sm:inline-flex">
                {staffLabel}
              </div>
            ) : null}

            <div className="flex min-w-0 items-center gap-2.5 rounded-2xl border border-[var(--color-border)] bg-white py-1.5 pl-1.5 pr-3 shadow-sm">
              <Avatar name={user?.full_name || ''} photoUrl={user?.photo_url} size="sm" />
              <div className="min-w-0 hidden sm:block">
                <p className="truncate text-sm font-semibold text-[var(--color-charcoal)]">
                  {user?.full_name || 'User'}
                </p>
                <p className="truncate text-xs text-slate-500">{user?.username}</p>
              </div>
            </div>
          </div>
        </header>

        <main className="min-h-0 flex-1 overflow-x-hidden overflow-y-auto overscroll-contain px-3 pb-5 sm:px-6 sm:pb-8">
          <Outlet />
        </main>
      </div>
    </div>
  )
}

export const orgNav: NavItemDef[] = [
  { to: '', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/people', label: 'Individuals', icon: Users },
  { to: '/alerts', label: 'Alerts', icon: AlertTriangle },
  { to: '/incidents', label: 'Incidents', icon: Activity },
  { to: '/responders', label: 'Responders', icon: Shield },
  { to: '/reports', label: 'Reports', icon: ClipboardList },
  { to: '/settings', label: 'Settings', icon: Settings },
  { to: '/profile', label: 'My profile', icon: UserRound },
]

export const registrarNav: NavItemDef[] = [
  { to: '/users', label: 'Users', icon: Users },
  { to: '/settings', label: 'Settings', icon: Settings },
]

export const individualNav: NavItemDef[] = [
  { to: '', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/bracelet', label: 'My Bracelet', icon: Watch },
  { to: '/alerts', label: 'My Alerts', icon: AlertTriangle },
  { to: '/incidents', label: 'My Incidents', icon: Activity },
  { to: '/contacts', label: 'Trusted Contacts', icon: Contact },
  { to: '/profile', label: 'Profile', icon: UserRound },
]

export const adminNav: NavItemDef[] = [
  { to: '', label: 'Overview', icon: LayoutDashboard },
  { to: '/organizations', label: 'Organizations', icon: Building2 },
  { to: '/users', label: 'Users', icon: Users },
  { to: '/alerts', label: 'Alerts', icon: AlertTriangle },
  { to: '/sms', label: 'SMS', icon: MessageSquare },
  { to: '/incidents', label: 'Incidents', icon: Activity },
  { to: '/reports', label: 'Reports', icon: FileText },
  { to: '/audit', label: 'Audit Logs', icon: ScrollText },
  { to: '/settings', label: 'Settings', icon: Settings },
]

export function AuthLayout({
  children,
  title,
  subtitle,
}: {
  children: React.ReactNode
  title?: string
  subtitle?: string
}) {
  return (
    <div className="grid min-h-screen lg:grid-cols-[1.05fr_0.95fr]">
      <aside className="auth-brand relative hidden overflow-hidden lg:flex lg:flex-col lg:justify-between lg:p-12 xl:p-16">
        <div className="auth-brand-mesh" aria-hidden />
        <div className="auth-brand-orb auth-brand-orb-a" aria-hidden />
        <div className="auth-brand-orb auth-brand-orb-b" aria-hidden />
        <div className="relative z-10">
          <img
            src="/logo.png"
            alt="SafeBangle"
            className="h-12 w-12 rounded-xl object-cover shadow-lg ring-1 ring-white/25"
          />
        </div>
        <div className="relative z-10 max-w-lg">
          <h2 className="font-display text-4xl leading-tight text-white xl:text-5xl">
            Protection that travels with every bracelet.
          </h2>
          <p className="mt-6 text-base leading-relaxed text-blue-100/90 xl:text-lg">
            Real-time alerts, incident response, and device monitoring for organizations
            and individuals who need reliable safety coverage.
          </p>
        </div>
        <p className="relative z-10 text-xs text-blue-100/60">
          Secure access · Incident response · Device monitoring
        </p>
      </aside>

      <main className="relative flex min-h-screen flex-col justify-center bg-[#f7f8fb] px-5 py-10 sm:px-10 lg:px-14 xl:px-16">
        <div className="auth-form-wash" aria-hidden />
        <div className="relative z-10 mx-auto w-full max-w-[440px]">
          <div className="mb-8 flex items-center gap-3">
            <img
              src="/logo.png"
              alt="SafeBangle"
              className="h-12 w-12 rounded-2xl object-cover shadow-md ring-1 ring-black/5 sm:h-14 sm:w-14"
            />
            <div className="min-w-0">
              <p className="font-display text-xl tracking-tight">
                <span className="brand-safe">Safe</span>
                <span className="brand-bangle">Bangle</span>
              </p>
              <p className="text-xs text-slate-500">Bracelet safety platform</p>
            </div>
          </div>

          {title ? (
            <h1 className="text-[1.45rem] font-semibold leading-tight tracking-tight text-[var(--color-charcoal)] sm:text-[1.7rem]">
              {title}
            </h1>
          ) : null}
          {subtitle ? (
            <p className="mt-2 text-sm leading-relaxed text-slate-500 sm:text-[15px]">{subtitle}</p>
          ) : null}

          <div className="mt-8">{children}</div>
        </div>
      </main>
    </div>
  )
}
