import { useState } from 'react'
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import axios from 'axios'
import { toast } from 'sonner'
import { getErrorMessage, useAuth } from '../api/auth'
import { authApi, orgApi } from '../api/services'
import { AuthLayout } from '../layouts/AppShell'
import { useGeo } from '../components/PhoneInput'
import { Button, Input, PasswordInput } from '../components/ui'

function isEmail(identifier: string) {
  return identifier.includes('@')
}

/** Identifier passed to /verify-email in router state, so phone numbers stay out of the URL. */
function useIdentifierFromRoute() {
  const location = useLocation()
  const [params] = useSearchParams()
  const state = location.state as { identifier?: string } | null
  return state?.identifier || params.get('email') || ''
}

function Field({
  label,
  children,
  hint,
}: {
  label: string
  children: React.ReactNode
  hint?: string
}) {
  return (
    <label className="block space-y-1.5">
      <span className="text-sm font-medium text-[var(--color-charcoal)]">{label}</span>
      {children}
      {hint ? <span className="block text-xs text-slate-400">{hint}</span> : null}
    </label>
  )
}

function StepLabel({ step, total }: { step: number; total: number }) {
  return (
    <p className="mb-6 text-sm text-slate-500">
      Step {step} of {total}
      <span className="mt-2 block h-1 overflow-hidden rounded-full bg-slate-200">
        <span
          className="block h-full rounded-full bg-[var(--color-blue)] transition-all"
          style={{ width: `${(step / total) * 100}%` }}
        />
      </span>
    </p>
  )
}

function CodeInput(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <Input
      {...props}
      inputMode="numeric"
      autoComplete="one-time-code"
      maxLength={6}
      className={`tracking-[0.35em] text-center text-lg font-semibold ${props.className ?? ''}`}
      placeholder="000000"
    />
  )
}

export function LoginPage() {
  const { login } = useAuth()
  const navigate = useNavigate()
  const geo = useGeo()
  const [identifier, setIdentifier] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      await login(identifier.trim(), password, geo.data?.country_code)
      toast.success('Signed in')
      navigate('/')
    } catch (err) {
      if (axios.isAxiosError(err)) {
        const data = err.response?.data as {
          requires_verification?: boolean
          identifier?: string
          error?: string
        }
        if (data?.requires_verification) {
          toast.success(data.error || 'We sent you a verification code')
          navigate('/verify-email', { state: { identifier: data.identifier || identifier.trim() } })
          return
        }
      }
      toast.error(getErrorMessage(err))
    } finally {
      setLoading(false)
    }
  }

  return (
    <AuthLayout title="Sign in" subtitle="Access your SafeBangle console.">
      <form onSubmit={onSubmit} className="space-y-5">
        <Field label="Username, phone number or email">
          <Input
            placeholder="amina4821"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            required
            autoComplete="username"
          />
        </Field>
        <Field label="Password">
          <PasswordInput
            placeholder="Your password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            autoComplete="current-password"
          />
        </Field>
        <div className="flex justify-end">
          <Link className="text-sm text-[var(--color-blue)] hover:underline" to="/forgot-password">
            Set or reset password
          </Link>
        </div>
        <Button type="submit" className="h-11 w-full" disabled={loading}>
          {loading ? 'Signing in…' : 'Sign in'}
        </Button>
      </form>
      <p className="mt-8 text-sm text-slate-500">
        SafeBangle staff create accounts. Need one? Please contact us.
      </p>
    </AuthLayout>
  )
}

export function VerifyEmailPage() {
  const navigate = useNavigate()
  const { completeLogin } = useAuth()
  const geo = useGeo()
  const routed = useIdentifierFromRoute()
  const [identifier, setIdentifier] = useState(routed)
  const [code, setCode] = useState('')
  const [loading, setLoading] = useState(false)
  const [resending, setResending] = useState(false)
  const byEmail = isEmail(identifier)

  const verify = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!identifier.trim() || code.length !== 6) {
      toast.error('Enter your username, phone number or email and the 6-digit code')
      return
    }
    setLoading(true)
    try {
      const { data } = await authApi.verifyCode(identifier.trim(), code.trim(), geo.data?.country_code)
      completeLogin(data)
      toast.success('Verified')
      navigate('/')
    } catch (err) {
      toast.error(getErrorMessage(err))
    } finally {
      setLoading(false)
    }
  }

  const resend = async () => {
    if (!identifier.trim()) {
      toast.error('Enter your username, phone number or email first')
      return
    }
    setResending(true)
    try {
      const { data } = await authApi.resendCode(identifier.trim(), geo.data?.country_code)
      toast.success(data.message || 'If that account exists, a new code was sent.')
    } catch (err) {
      toast.error(getErrorMessage(err))
    } finally {
      setResending(false)
    }
  }

  return (
    <AuthLayout
      title={byEmail ? 'Verify your email' : 'Verify your phone'}
      subtitle={
        byEmail
          ? 'Check your inbox for an email from SafeBangle with a 6-digit code. It expires in 15 minutes.'
          : 'We texted you a 6-digit code from SafeBangle. It expires in 15 minutes.'
      }
    >
      <form onSubmit={verify} className="space-y-5">
        <Field label="Username, phone number or email">
          <Input
            required
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            placeholder="amina4821"
          />
        </Field>
        <Field label="Verification code">
          <CodeInput value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))} required />
        </Field>
        <Button type="submit" className="h-11 w-full" disabled={loading}>
          {loading ? 'Verifying…' : 'Verify'}
        </Button>
      </form>
      <button
        type="button"
        className="mt-4 text-sm font-medium text-[var(--color-blue)] hover:underline"
        onClick={resend}
        disabled={resending}
      >
        {resending ? 'Sending…' : 'Resend code'}
      </button>
      <Link className="mt-6 block text-sm text-slate-500 hover:text-[var(--color-blue)]" to="/login">
        Back to sign in
      </Link>
    </AuthLayout>
  )
}

export function ForgotPasswordPage() {
  const navigate = useNavigate()
  const geo = useGeo()
  const [step, setStep] = useState<1 | 2 | 3>(1)
  const [identifier, setIdentifier] = useState('')
  const [code, setCode] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [loading, setLoading] = useState(false)
  const [resending, setResending] = useState(false)

  const titles = {
    1: {
      title: 'Set or reset password',
      subtitle: 'Enter your username, phone number or email. We will send you a 6-digit code.',
    },
    2: {
      title: 'Enter your code',
      subtitle: isEmail(identifier)
        ? 'Check your inbox for the code.'
        : 'Check your text messages for the code. It may go to your email if you have no phone on your account.',
    },
    3: { title: 'Choose a password', subtitle: 'Choose a password for your account.' },
  }

  const resend = async () => {
    if (!identifier.trim()) {
      toast.error('Enter your username, phone number or email first')
      return
    }
    setResending(true)
    try {
      const { data } = await authApi.forgotPassword(identifier.trim(), geo.data?.country_code)
      toast.success(data.message || 'If that account exists, a code was sent.')
    } catch (err) {
      toast.error(getErrorMessage(err))
    } finally {
      setResending(false)
    }
  }

  return (
    <AuthLayout title={titles[step].title} subtitle={titles[step].subtitle}>
      <StepLabel step={step} total={3} />
      <form
        className="space-y-5"
        onSubmit={async (e) => {
          e.preventDefault()
          setLoading(true)
          try {
            if (step === 1) {
              const { data } = await authApi.forgotPassword(identifier.trim(), geo.data?.country_code)
              toast.success(data.message || 'If that account exists, a code was sent.')
              setStep(2)
            } else if (step === 2) {
              if (code.length !== 6) {
                toast.error('Enter the 6-digit code')
                return
              }
              setStep(3)
            } else {
              if (password.length < 8) {
                toast.error('Password must be at least 8 characters')
                return
              }
              if (password !== confirm) {
                toast.error('Passwords do not match')
                return
              }
              await authApi.resetPassword(identifier.trim(), code.trim(), password, geo.data?.country_code)
              toast.success('Password updated')
              navigate('/login')
            }
          } catch (err) {
            toast.error(getErrorMessage(err))
          } finally {
            setLoading(false)
          }
        }}
      >
        {step === 1 ? (
          <Field label="Username, phone number or email">
            <Input required value={identifier} onChange={(e) => setIdentifier(e.target.value)} placeholder="amina4821" />
          </Field>
        ) : null}
        {step === 2 ? (
          <>
            <p className="text-sm text-slate-500">If that account exists, we sent a code for {identifier}</p>
            <Field label="Code">
              <CodeInput value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))} required />
            </Field>
          </>
        ) : null}
        {step === 3 ? (
          <>
            <Field label="New password">
              <PasswordInput required value={password} onChange={(e) => setPassword(e.target.value)} placeholder="New password" />
            </Field>
            <Field label="Confirm password">
              <PasswordInput required value={confirm} onChange={(e) => setConfirm(e.target.value)} placeholder="Repeat password" />
            </Field>
          </>
        ) : null}
        <div className="flex gap-3">
          {step > 1 ? (
            <Button type="button" variant="secondary" className="h-11 flex-1" onClick={() => setStep((s) => (s === 3 ? 2 : 1))}>
              Back
            </Button>
          ) : null}
          <Button type="submit" className="h-11 flex-1" disabled={loading}>
            {loading
              ? 'Please wait…'
              : step === 1
                ? 'Send code'
                : step === 2
                  ? 'Continue'
                  : 'Save password'}
          </Button>
        </div>
      </form>
      {step === 2 ? (
        <button
          type="button"
          className="mt-4 text-sm font-medium text-[var(--color-blue)] hover:underline disabled:opacity-60"
          onClick={resend}
          disabled={resending}
        >
          {resending ? 'Sending…' : 'Resend code'}
        </button>
      ) : null}
      <Link className="mt-8 block text-sm font-medium text-[var(--color-blue)]" to="/login">
        Back to sign in
      </Link>
    </AuthLayout>
  )
}

/** Kept for old links — redirects into forgot-password flow. */
export function ResetPasswordPage() {
  return <ForgotPasswordPage />
}

export function AcceptInvitePage() {
  const [params] = useSearchParams()
  const navigate = useNavigate()
  const { user } = useAuth()
  return (
    <AuthLayout title="Join organization" subtitle="Accept the invitation to open the organization console.">
      <Button
        type="button"
        className="h-11 w-full"
        onClick={async () => {
          if (!user) {
            navigate(`/login`)
            return
          }
          try {
            await orgApi.acceptInvite(params.get('token') || '')
            toast.success('Joined organization')
            navigate('/app')
          } catch (e) {
            toast.error(getErrorMessage(e))
          }
        }}
      >
        Accept invitation
      </Button>
    </AuthLayout>
  )
}
