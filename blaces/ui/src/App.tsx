import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from './api/auth'
import { LoadingState } from './components/ui'
import { AppShell, adminNav, individualNav, orgNav, registrarNav } from './layouts/AppShell'
import {
  AcceptInvitePage,
  ForgotPasswordPage,
  LoginPage,
  ResetPasswordPage,
  VerifyEmailPage,
} from './pages/Auth'
import {
  AdminAlerts,
  AdminAudit,
  AdminIncidents,
  AdminOrganizations,
  AdminOverview,
  AdminReports,
  AdminSettings,
  AdminSms,
  AdminUsers,
} from './pages/Admin'
import { AdminOrganizationDetail } from './pages/AdminOrganizationDetail'
import { AdminUserDetail } from './pages/AdminUserDetail'
import {
  IndividualDashboard,
  MyAlertsPage,
  MyBraceletPage,
  MyContactsPage,
  MyIncidentsPage,
  ProfilePage,
} from './pages/Individual'
import { AlertsPage } from './pages/org/Alerts'
import { OrgDashboard } from './pages/org/Dashboard'
import { IncidentDetailPage, IncidentsPage } from './pages/org/Incidents'
import { PeoplePage } from './pages/org/People'
import { OrgSettingsPage, ReportsPage, RespondersPage } from './pages/org/ReportsSettings'

function HomeRedirect() {
  const { user, loading } = useAuth()
  if (loading) return <LoadingState />
  if (!user) return <Navigate to="/login" replace />
  if (user.is_platform_admin) return <Navigate to="/admin" replace />
  if (user.platform_role === 'registrar') return <Navigate to="/admin/users" replace />
  if (user.account_type === 'organization' || user.memberships?.length) {
    return <Navigate to="/app" replace />
  }
  return <Navigate to="/me" replace />
}

/** The staff console: full for super admins, Users and Settings for registrars. */
function StaffConsole() {
  const { user, loading } = useAuth()
  if (loading) return <LoadingState />
  if (!user) return <Navigate to="/login" replace />
  if (user.is_platform_admin) return <AppShell nav={adminNav} base="/admin" mode="admin" />
  if (user.platform_role === 'registrar') {
    return <AppShell nav={registrarNav} base="/admin" mode="admin" />
  }
  return <Navigate to="/" replace />
}

function SuperAdminOnly({ children }: { children: React.ReactNode }) {
  const { user } = useAuth()
  if (!user?.is_platform_admin) return <Navigate to="/admin/users" replace />
  return children
}

/** Org accounts belong in /app — don't leave them on the personal /me console. */
function RequireOrgConsole({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth()
  if (loading) return <LoadingState />
  if (!user) return <Navigate to="/login" replace />
  if (user.is_platform_admin) return <Navigate to="/admin" replace />
  if (user.account_type === 'individual' && !user.memberships?.length) {
    return <Navigate to="/me" replace />
  }
  return children
}

/** Personal console — bounce organization users to /app. */
function RequireIndividualConsole({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth()
  if (loading) return <LoadingState />
  if (!user) return <Navigate to="/login" replace />
  if (user.is_platform_admin) return <Navigate to="/admin" replace />
  if (user.platform_role === 'registrar') return <Navigate to="/admin/users" replace />
  if (user.account_type === 'organization' || user.memberships?.length) {
    return <Navigate to="/app" replace />
  }
  return children
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/verify-email" element={<VerifyEmailPage />} />
      <Route path="/forgot-password" element={<ForgotPasswordPage />} />
      <Route path="/reset-password" element={<ResetPasswordPage />} />
      <Route path="/accept-invite" element={<AcceptInvitePage />} />
      <Route path="/" element={<HomeRedirect />} />

      <Route
        path="/app"
        element={
          <RequireOrgConsole>
            <AppShell nav={orgNav} base="/app" mode="organization" />
          </RequireOrgConsole>
        }
      >
        <Route index element={<OrgDashboard />} />
        <Route path="people" element={<PeoplePage />} />
        <Route path="bracelets" element={<Navigate to="/app/people" replace />} />
        <Route path="alerts" element={<AlertsPage />} />
        <Route path="incidents" element={<IncidentsPage />} />
        <Route path="incidents/:id" element={<IncidentDetailPage />} />
        <Route path="responders" element={<RespondersPage />} />
        <Route path="reports" element={<ReportsPage />} />
        <Route path="settings" element={<OrgSettingsPage />} />
        <Route path="profile" element={<ProfilePage />} />
      </Route>

      <Route
        path="/me"
        element={
          <RequireIndividualConsole>
            <AppShell nav={individualNav} base="/me" mode="individual" />
          </RequireIndividualConsole>
        }
      >
        <Route index element={<IndividualDashboard />} />
        <Route path="bracelet" element={<MyBraceletPage />} />
        <Route path="alerts" element={<MyAlertsPage />} />
        <Route path="incidents" element={<MyIncidentsPage />} />
        <Route path="incidents/:id" element={<IncidentDetailPage />} />
        <Route path="contacts" element={<MyContactsPage />} />
        <Route path="profile" element={<ProfilePage />} />
      </Route>

      <Route path="/admin" element={<StaffConsole />}>
        <Route index element={<SuperAdminOnly><AdminOverview /></SuperAdminOnly>} />
        <Route path="users" element={<AdminUsers />} />
        <Route path="users/:id" element={<AdminUserDetail />} />
        <Route path="settings" element={<AdminSettings />} />
        <Route path="organizations" element={<SuperAdminOnly><AdminOrganizations /></SuperAdminOnly>} />
        <Route
          path="organizations/:id"
          element={<SuperAdminOnly><AdminOrganizationDetail /></SuperAdminOnly>}
        />
        <Route path="bracelets" element={<Navigate to="/admin/users" replace />} />
        <Route path="alerts" element={<SuperAdminOnly><AdminAlerts /></SuperAdminOnly>} />
        <Route path="sms" element={<SuperAdminOnly><AdminSms /></SuperAdminOnly>} />
        <Route path="incidents" element={<SuperAdminOnly><AdminIncidents /></SuperAdminOnly>} />
        <Route path="incidents/:id" element={<SuperAdminOnly><IncidentDetailPage /></SuperAdminOnly>} />
        <Route path="reports" element={<SuperAdminOnly><AdminReports /></SuperAdminOnly>} />
        <Route path="audit" element={<SuperAdminOnly><AdminAudit /></SuperAdminOnly>} />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
