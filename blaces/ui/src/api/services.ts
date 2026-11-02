import { api } from './client'
import type {
  Alert,
  AuditLog,
  Bracelet,
  CreatedUser,
  DashboardSummary,
  Incident,
  Invitation,
  Notification,
  Organization,
  OrganizationOnboardResult,
  OrgMember,
  Paginated,
  Person,
  ReportSummary,
  SmsMessage,
  SmsStats,
  StaffMember,
  TrustedContact,
  UpcomingBirthday,
  User,
  UserDetail,
} from '../types'

function photoForm(file: File) {
  const form = new FormData()
  form.append('photo', file)
  return form
}

// The client defaults to JSON; this makes axios send the file with a multipart boundary.
const MULTIPART = { headers: { 'Content-Type': 'multipart/form-data' } }

export const authApi = {
  login: (identifier: string, password: string, country_code?: string) =>
    api.post<{ user: User; tokens: { access: string; refresh: string } }>('/auth/login/', {
      identifier,
      password,
      country_code,
    }),
  me: () => api.get<User>('/auth/me/'),
  updateMe: (payload: Partial<User>) => api.patch<User>('/auth/me/', payload),
  uploadMyPhoto: (file: File) => api.post<User>('/auth/me/photo/', photoForm(file), MULTIPART),
  removeMyPhoto: () => api.delete<User>('/auth/me/photo/'),
  geo: () =>
    api.get<{
      country_code: string
      country_name: string
      dial_code: string
      dial_codes: { iso2: string; name: string; dial_code: string }[]
    }>('/auth/geo/'),
  verifyCode: (identifier: string, code: string, country_code?: string) =>
    api.post<{
      message: string
      user: User
      tokens: { access: string; refresh: string }
    }>('/auth/verify-phone/', { identifier, code, country_code }),
  resendCode: (identifier: string, country_code?: string) =>
    api.post<{ message: string }>('/auth/resend-code/', { identifier, country_code }),
  forgotPassword: (identifier: string, country_code?: string) =>
    api.post<{ message: string }>('/auth/forgot-password/', {
      identifier,
      country_code,
    }),
  resetPassword: (identifier: string, code: string, password: string, country_code?: string) =>
    api.post('/auth/reset-password/', { identifier, code, password, country_code }),
  changePassword: (current_password: string, new_password: string) =>
    api.post<{ message: string }>('/auth/change-password/', {
      current_password,
      new_password,
    }),
}

export const orgApi = {
  list: (params?: Record<string, string>) =>
    api.get<Paginated<Organization> | Organization[]>('/organizations/', { params }),
  get: (id: string) => api.get<Organization>(`/organizations/${id}/`),
  onboard: (payload: Record<string, unknown>) =>
    api.post<OrganizationOnboardResult>('/organizations/onboard/', payload),
  update: (id: string, payload: Record<string, unknown>) =>
    api.patch<Organization>(`/organizations/${id}/`, payload),
  remove: (id: string) => api.delete(`/organizations/${id}/`),
  activate: (id: string) => api.post<Organization>(`/organizations/${id}/activate/`),
  deactivate: (id: string) => api.post<Organization>(`/organizations/${id}/deactivate/`),
  members: (id: string) => api.get<OrgMember[]>(`/organizations/${id}/members/`),
  addMember: (id: string, payload: { identifier: string; role: string }) =>
    api.post<OrgMember>(`/organizations/${id}/members/`, payload),
  updateMember: (id: string, membershipId: string, role: string) =>
    api.patch<OrgMember>(`/organizations/${id}/members/${membershipId}/`, { role }),
  removeMember: (id: string, membershipId: string) =>
    api.delete(`/organizations/${id}/members/${membershipId}/`),
  invitations: (id: string) => api.get<Invitation[]>(`/organizations/${id}/invitations/`),
  invite: (
    id: string,
    payload: { first_name?: string; phone?: string; email?: string; role: string },
  ) => api.post<Invitation | { joined: true }>(`/organizations/${id}/invitations/`, payload),
  acceptInvite: (token: string) => api.post('/invitations/accept/', { token }),
}

export const peopleApi = {
  list: (params?: Record<string, string>) =>
    api.get<Paginated<Person>>('/people/', { params }),
  get: (id: string) => api.get<Person>(`/people/${id}/`),
  create: (payload: Record<string, unknown>) => api.post<Person>('/people/', payload),
  update: (id: string, payload: Record<string, unknown>) =>
    api.patch<Person>(`/people/${id}/`, payload),
  remove: (id: string) => api.delete(`/people/${id}/`),
  removeFromOrganization: (id: string) =>
    api.post<{ outcome: 'independent' | 'deleted' }>(`/people/${id}/remove-from-organization/`),
}

export const braceletApi = {
  list: (params?: Record<string, string>) =>
    api.get<Paginated<Bracelet>>('/bracelets/', { params }),
  get: (id: string) => api.get<Bracelet>(`/bracelets/${id}/`),
  create: (payload: Record<string, unknown>) => api.post<Bracelet>('/bracelets/', payload),
  update: (id: string, payload: Record<string, unknown>) =>
    api.patch<Bracelet>(`/bracelets/${id}/`, payload),
  assign: (id: string, person_id: string, reason?: string) =>
    api.post(`/bracelets/${id}/assign/`, { person_id, reason }),
  unassign: (id: string) => api.post(`/bracelets/${id}/unassign/`),
  activate: (id: string) => api.post(`/bracelets/${id}/activate/`),
  deactivate: (id: string) => api.post(`/bracelets/${id}/deactivate/`),
  history: (id: string) => api.get(`/bracelets/${id}/history/`),
}

export const alertApi = {
  list: (params?: Record<string, string>) => api.get<Paginated<Alert>>('/alerts/', { params }),
  get: (id: string) => api.get<Alert>(`/alerts/${id}/`),
}

export const incidentApi = {
  list: (params?: Record<string, string>) =>
    api.get<Paginated<Incident>>('/incidents/', { params }),
  get: (id: string) => api.get<Incident>(`/incidents/${id}/`),
  acknowledge: (id: string, note?: string) =>
    api.post<Incident>(`/incidents/${id}/acknowledge/`, { note }),
  assign: (id: string, responder_id?: string) =>
    api.post<Incident>(`/incidents/${id}/assign/`, { responder_id }),
  respond: (id: string) => api.post<Incident>(`/incidents/${id}/respond/`),
  resolve: (id: string, resolution: string) =>
    api.post<Incident>(`/incidents/${id}/resolve/`, { resolution }),
  close: (id: string) => api.post<Incident>(`/incidents/${id}/close/`),
  addNote: (id: string, note: string) =>
    api.post<Incident>(`/incidents/${id}/add_note/`, { note }),
}

export const contactApi = {
  list: (params?: Record<string, string>) =>
    api.get<Paginated<TrustedContact>>('/trusted-contacts/', { params }),
  create: (payload: Record<string, unknown>) =>
    api.post<TrustedContact>('/trusted-contacts/', payload),
  update: (id: string, payload: Record<string, unknown>) =>
    api.patch<TrustedContact>(`/trusted-contacts/${id}/`, payload),
  remove: (id: string) => api.delete(`/trusted-contacts/${id}/`),
}

export const dashboardApi = {
  summary: (params?: Record<string, string>) =>
    api.get<DashboardSummary>('/dashboard/summary/', { params }),
}

export const reportApi = {
  summary: (params?: Record<string, string>) =>
    api.get<ReportSummary>('/reports/summary/', { params }),
}

export const notificationApi = {
  list: (params?: Record<string, string>) =>
    api.get<Paginated<Notification>>('/notifications/', { params }),
  markRead: (id: string) => api.post(`/notifications/${id}/mark_read/`),
}

export const auditApi = {
  list: (params?: Record<string, string>) =>
    api.get<Paginated<AuditLog>>('/audit-logs/', { params }),
}

export const smsApi = {
  list: (params?: Record<string, string>) =>
    api.get<Paginated<SmsMessage>>('/sms-messages/', { params }),
  stats: (params?: Record<string, string>) =>
    api.get<SmsStats>('/sms-messages/stats/', { params }),
}

export const usersApi = {
  upcomingBirthdays: () => api.get<UpcomingBirthday[]>('/auth/users/upcoming-birthdays/'),
  list: (params?: Record<string, string>) =>
    api.get<Paginated<User>>('/auth/users/', { params }),
  get: (id: string) => api.get<UserDetail>(`/auth/users/${id}/`),
  create: (payload: Record<string, unknown>) => api.post<CreatedUser>('/auth/users/', payload),
  replaceDevice: (
    id: string,
    payload: { device_id: string; old_device_state: string; reason: string },
  ) => api.post<UserDetail>(`/auth/users/${id}/replace-device/`, payload),
  uploadPhoto: (id: string, file: File) =>
    api.post<UserDetail>(`/auth/users/${id}/photo/`, photoForm(file), MULTIPART),
  removePhoto: (id: string) => api.delete<UserDetail>(`/auth/users/${id}/photo/`),
  update: (id: string, payload: Record<string, unknown>) =>
    api.patch<User>(`/auth/users/${id}/`, payload),
  remove: (id: string) => api.delete(`/auth/users/${id}/`),
  mute: (id: string) => api.post<User>(`/auth/users/${id}/mute/`),
  unmute: (id: string) => api.post<User>(`/auth/users/${id}/unmute/`),
  block: (id: string) => api.post<User>(`/auth/users/${id}/block/`),
  unblock: (id: string) => api.post<User>(`/auth/users/${id}/unblock/`),
}

export const staffApi = {
  list: () => api.get<StaffMember[]>('/auth/staff/'),
  invite: (payload: Record<string, unknown>) =>
    api.post<StaffMember & { sms_sent: boolean; sms_error: string }>(
      '/auth/staff/invite/',
      payload,
    ),
  resend: (id: string) =>
    api.post<{ sms_sent: boolean; sms_error: string }>(`/auth/staff/${id}/resend/`),
  removeRole: (id: string) => api.post(`/auth/staff/${id}/remove-role/`),
}

export function unwrapList<T>(data: Paginated<T> | T[]): T[] {
  if (Array.isArray(data)) return data
  return data.results ?? []
}
