import { useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { ArrowUpRight } from 'lucide-react'

export function StatCard({
  label,
  value,
  hint,
  tone = 'default',
  featured = false,
}: {
  label: string
  value: string | number
  hint?: string
  tone?: 'default' | 'danger' | 'ok'
  featured?: boolean
}) {
  if (featured) {
    return (
      <div className="admin-stat-featured console-stat-featured relative overflow-hidden p-4 sm:p-5">
        <div
          className="pointer-events-none absolute -right-6 -top-8 h-28 w-28 rounded-full bg-white/10"
          aria-hidden
        />
        <div className="relative flex items-start justify-between gap-3">
          <p className="text-sm font-medium text-blue-100">{label}</p>
          <span className="inline-flex h-8 w-8 items-center justify-center rounded-xl bg-white/15 text-white">
            <ArrowUpRight className="h-4 w-4" />
          </span>
        </div>
        <p className="relative mt-4 text-3xl font-semibold tracking-tight text-white sm:text-4xl">
          {value}
        </p>
        {hint ? <p className="relative mt-2 text-xs text-blue-100/85">{hint}</p> : null}
      </div>
    )
  }

  const toneClass =
    tone === 'danger'
      ? 'border-[var(--color-red)]/20 bg-[var(--color-red-soft)]'
      : tone === 'ok'
        ? 'border-emerald-100 bg-emerald-50/80'
        : 'console-card'

  return (
    <div className={`rounded-[1.35rem] p-4 sm:p-5 ${toneClass}`}>
      <div className="flex items-start justify-between gap-3">
        <p className="text-sm font-medium text-slate-500">{label}</p>
        <span
          className={`inline-flex h-8 w-8 items-center justify-center rounded-xl ${
            tone === 'danger'
              ? 'bg-white text-[var(--color-red)]'
              : tone === 'ok'
                ? 'bg-white text-emerald-700'
                : 'bg-[var(--color-surface)] text-[var(--color-blue)]'
          }`}
        >
          <ArrowUpRight className="h-4 w-4" />
        </span>
      </div>
      <p className="mt-4 text-3xl font-semibold tracking-tight text-[var(--color-charcoal)] sm:text-4xl">
        {value}
      </p>
      {hint ? <p className="mt-2 text-xs text-slate-500">{hint}</p> : null}
    </div>
  )
}

export function StatusBadge({ status }: { status: string }) {
  const s = status.toUpperCase()
  const critical = ['NEW', 'SOS', 'RESPONDING', 'CRITICAL', 'FAILED', 'BLOCKED'].some((x) =>
    s.includes(x),
  )
  const ok = [
    'RESOLVED',
    'CLOSED',
    'IN_USE',
    'PROCESSED',
    'ACTIVATED',
    'COMPLETED',
    'SENT',
    'DELIVERED',
    'RECEIVED',
    'ACTIVE',
  ].includes(s)
  const muted = s === 'MUTED'
  const cls = critical
    ? 'bg-[var(--color-red-soft)] text-[var(--color-red)]'
    : muted
      ? 'bg-amber-50 text-amber-700'
      : ok
        ? 'bg-emerald-50 text-emerald-700'
        : 'bg-slate-100 text-slate-600'
  return (
    <span
      className={`inline-flex rounded-xl px-2.5 py-1 text-[11px] font-semibold tracking-wide ${cls}`}
    >
      {status}
    </span>
  )
}

export function EmptyState({
  title,
  description,
  actionLabel,
  onAction,
  to,
}: {
  title: string
  description?: string
  actionLabel?: string
  onAction?: () => void
  to?: string
}) {
  return (
    <div className="console-card px-6 py-12 text-center">
      <h3 className="text-lg font-semibold text-[var(--color-charcoal)]">{title}</h3>
      {description ? <p className="mx-auto mt-2 max-w-md text-sm text-slate-500">{description}</p> : null}
      {actionLabel && to ? (
        <Link
          to={to}
          className="mt-5 inline-flex rounded-xl bg-[var(--color-blue)] px-4 py-2.5 text-sm font-semibold text-white hover:bg-[var(--color-blue-dark)]"
        >
          {actionLabel}
        </Link>
      ) : null}
      {actionLabel && onAction ? (
        <button
          type="button"
          onClick={onAction}
          className="mt-5 inline-flex rounded-xl bg-[var(--color-blue)] px-4 py-2.5 text-sm font-semibold text-white hover:bg-[var(--color-blue-dark)]"
        >
          {actionLabel}
        </button>
      ) : null}
    </div>
  )
}

export function LoadingState({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="flex items-center justify-center py-16 text-slate-500">
      <div className="h-5 w-5 animate-spin rounded-full border-2 border-[var(--color-blue)] border-t-transparent" />
      <span className="ml-3 text-sm">{label}</span>
    </div>
  )
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="rounded-[1.35rem] border border-red-200 bg-[var(--color-red-soft)] px-4 py-6 text-center">
      <p className="text-sm text-[var(--color-red)]">{message}</p>
      {onRetry ? (
        <button
          type="button"
          onClick={onRetry}
          className="mt-3 text-sm font-medium text-[var(--color-blue)] underline"
        >
          Try again
        </button>
      ) : null}
    </div>
  )
}

export function PageHeader({
  title,
  subtitle,
  actions,
}: {
  title: string
  subtitle?: string
  actions?: ReactNode
}) {
  return (
    <div className="mb-5 flex flex-col gap-3 sm:mb-6 sm:flex-row sm:items-end sm:justify-between">
      <div className="min-w-0">
        <h1 className="font-display text-2xl text-[var(--color-charcoal)] sm:text-3xl">{title}</h1>
        {subtitle ? <p className="mt-1.5 text-sm text-slate-500">{subtitle}</p> : null}
      </div>
      {actions ? (
        <div className="flex w-full shrink-0 flex-wrap gap-2 sm:w-auto">{actions}</div>
      ) : null}
    </div>
  )
}

export function Button({
  children,
  variant = 'primary',
  className = '',
  type = 'button',
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'secondary' | 'danger' | 'ghost'
}) {
  const variants = {
    primary: 'bg-[var(--color-blue)] text-white hover:bg-[var(--color-blue-dark)]',
    secondary:
      'border border-[var(--color-border)] bg-white text-[var(--color-charcoal)] hover:bg-slate-50',
    danger: 'bg-[var(--color-red)] text-white hover:bg-red-700',
    ghost: 'text-[var(--color-blue)] hover:bg-blue-50',
  }
  return (
    <button
      type={type}
      className={`inline-flex items-center justify-center rounded-xl px-3.5 py-2.5 text-sm font-semibold disabled:opacity-50 ${variants[variant]} ${className}`}
      {...props}
    >
      {children}
    </button>
  )
}

export function Input(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={`w-full rounded-xl border border-[var(--color-border)] bg-white px-3.5 py-2.5 text-sm text-[var(--color-charcoal)] outline-none transition focus:border-[var(--color-blue)] focus:ring-4 focus:ring-[var(--color-blue)]/12 ${props.className ?? ''}`}
    />
  )
}

export function PasswordInput({
  className = '',
  ...props
}: Omit<React.InputHTMLAttributes<HTMLInputElement>, 'type'>) {
  const [visible, setVisible] = useState(false)
  return (
    <div className="relative">
      <input
        {...props}
        type={visible ? 'text' : 'password'}
        className={`w-full rounded-xl border border-[var(--color-border)] bg-white px-3.5 py-2.5 pr-16 text-sm text-[var(--color-charcoal)] outline-none transition focus:border-[var(--color-blue)] focus:ring-4 focus:ring-[var(--color-blue)]/12 ${className}`}
      />
      <button
        type="button"
        onClick={() => setVisible((v) => !v)}
        className="absolute right-3 top-1/2 -translate-y-1/2 text-sm font-medium text-[var(--color-blue)] hover:underline"
        tabIndex={-1}
      >
        {visible ? 'Hide' : 'Show'}
      </button>
    </div>
  )
}

export function Select(props: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={`w-full rounded-xl border border-[var(--color-border)] bg-white px-3.5 py-2.5 text-sm outline-none transition focus:border-[var(--color-blue)] focus:ring-4 focus:ring-[var(--color-blue)]/12 ${props.className ?? ''}`}
    />
  )
}

export function Textarea(props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      {...props}
      className={`w-full rounded-xl border border-[var(--color-border)] bg-white px-3 py-2 text-sm outline-none focus:border-[var(--color-blue)] ${props.className ?? ''}`}
    />
  )
}

export function Modal({
  open,
  title,
  children,
  onClose,
  size = 'md',
}: {
  open: boolean
  title: string
  children: ReactNode
  onClose: () => void
  size?: 'md' | 'lg'
}) {
  if (!open) return null
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 p-4 sm:items-center">
      <div
        className={`flex max-h-[90vh] w-full ${size === 'lg' ? 'max-w-2xl' : 'max-w-lg'} flex-col overflow-visible rounded-[1.35rem] bg-white p-5 shadow-xl`}
      >
        <div className="mb-4 flex shrink-0 items-center justify-between gap-3">
          <h2 className="text-lg font-semibold">{title}</h2>
          <button
            type="button"
            onClick={onClose}
            className="rounded-xl px-2 py-1 text-slate-400 hover:bg-slate-50 hover:text-slate-700"
          >
            ✕
          </button>
        </div>
        <div className="min-h-0 overflow-y-auto overflow-x-visible">{children}</div>
      </div>
    </div>
  )
}

export function SearchInput({
  value,
  onChange,
  placeholder = 'Search…',
}: {
  value: string
  onChange: (v: string) => void
  placeholder?: string
}) {
  return (
    <Input
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      className="w-full max-w-none sm:max-w-sm"
    />
  )
}

export function AdminCard({
  title,
  action,
  children,
  className = '',
}: {
  title: string
  action?: ReactNode
  children: ReactNode
  className?: string
}) {
  return (
    <section className={`admin-card overflow-hidden ${className}`}>
      <div className="flex items-center justify-between gap-3 px-5 py-4 sm:px-6">
        <h2 className="text-base font-semibold text-[var(--color-charcoal)]">{title}</h2>
        {action}
      </div>
      <div className="px-5 pb-5 sm:px-6 sm:pb-6">{children}</div>
    </section>
  )
}

export function SoftStatCard({
  label,
  value,
  hint,
  tone = 'default',
  to,
}: {
  label: string
  value: string | number
  hint?: string
  tone?: 'default' | 'danger' | 'ok' | 'featured'
  to?: string
}) {
  const card =
    tone === 'featured' ? (
      <StatCard label={label} value={value} hint={hint} featured />
    ) : (
      <div
        className={`admin-card rounded-[1.5rem] p-4 sm:p-5 ${
          tone === 'danger'
            ? 'border-[var(--color-red)]/20 bg-[var(--color-red-soft)]'
            : tone === 'ok'
              ? 'border-emerald-100 bg-emerald-50/80'
              : ''
        }`}
      >
        <div className="flex items-start justify-between gap-3">
          <p className="text-sm font-medium text-slate-500">{label}</p>
          <span
            className={`inline-flex h-8 w-8 items-center justify-center rounded-xl ${
              tone === 'danger'
                ? 'bg-white/70 text-[var(--color-red)]'
                : 'bg-slate-50 text-slate-400'
            }`}
          >
            <ArrowUpRight className="h-4 w-4" />
          </span>
        </div>
        <p className="mt-4 text-3xl font-semibold tracking-tight text-[var(--color-charcoal)] sm:text-4xl">
          {value}
        </p>
        {hint ? <p className="mt-2 text-xs text-slate-500">{hint}</p> : null}
      </div>
    )
  if (to) {
    return (
      <Link to={to} className="block transition hover:-translate-y-0.5 hover:opacity-95">
        {card}
      </Link>
    )
  }
  return card
}
