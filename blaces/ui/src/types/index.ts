export type MembershipRole = 'OWNER' | 'ADMIN' | 'STAFF' | 'RESPONDER' | 'VIEWER'

export interface Membership {
  id: string
  organization_id: string
  organization_name: string
  role: MembershipRole
  is_active: boolean
}

export interface User {
  id: string
  username: string
  email: string | null
  first_name: string
  last_name: string
  full_name: string
  phone: string | null
  is_platform_admin: boolean
  email_verified: boolean
  phone_verified: boolean
  is_active?: boolean
  is_muted?: boolean
  account_type: 'individual' | 'organization'
  country_code?: string
  city?: string
  address?: string
  photo_url?: string | null
  platform_role?: '' | 'registrar'
  has_device?: boolean
  device_id?: string | null
  organization_name?: string | null
  sex?: string
  date_of_birth?: string | null
  age?: number | null
  memberships: Membership[]
  bracelet_count?: number
  person_count?: number
  has_app_profile?: boolean
  has_watch?: boolean
  sources?: string[]
  status_label?: 'active' | 'muted' | 'blocked' | string
  created_at: string
  updated_at?: string
}

export interface UpcomingBirthday {
  id: string
  full_name: string
  photo_url: string | null
  days_away: number
  date: string
}

export interface CreatedUser extends User {
  sms_sent: boolean
  sms_error: string
}

export interface DeviceHistoryEntry {
  id: string
  device_id: string
  assigned_at: string
  unassigned_at: string | null
  reason: string
}

export interface UserDetail extends User {
  person_id: string | null
  current_device: Bracelet | null
  device_history: DeviceHistoryEntry[]
  registered_by_name: string | null
}

export interface StaffMember {
  id: string
  username: string
  full_name: string
  phone: string | null
  email: string | null
  platform_role: string
  is_active: boolean
  pending: boolean
  created_at: string
}

export interface Organization {
  id: string
  name: string
  slug: string
  description: string
  email: string
  phone: string
  address: string
  is_active: boolean
  member_count: number
  people_count: number
  created_at: string
}

export interface OrgMember {
  id: string
  user_id: string
  user_email: string | null
  user_phone: string | null
  user_name: string
  role: MembershipRole
  is_active: boolean
}

export interface Invitation {
  id: string
  email: string
  phone: string
  role: MembershipRole
  is_valid: boolean
}

export interface OrganizationOnboardResult {
  organization: Organization
  owner: {
    id: string
    full_name: string
    phone: string | null
    email: string | null
    is_new: boolean
  }
  sms_sent: boolean
  sms_error: string
}

export interface Person {
  id: string
  organization: string | null
  owner_user: string | null
  linked_user: string | null
  first_name: string
  last_name: string
  full_name: string
  email: string
  phone: string
  external_id: string
  notes: string
  is_active: boolean
  current_bracelet: { id: string; device_id: string; status: string } | null
  last_alert_at: string | null
  created_at: string
}

export interface Bracelet {
  id: string
  device_id: string
  serial_number: string
  status: string
  organization: string | null
  organization_name?: string | null
  owner_user: string | null
  current_person: string | null
  person_name: string | null
  activated_at: string | null
  notes: string
  last_alert_at: string | null
  created_at: string
}

export interface Alert {
  id: string
  bracelet: string | null
  device_id: string | null
  person: string | null
  person_name: string | null
  organization: string | null
  organization_name: string | null
  alert_code: string
  latitude: string | null
  longitude: string | null
  location_label: string
  location_area: string
  location_source: string
  location_accuracy_m: number | null
  received_at: string
  processing_status: string
  incident_id: string | null
  created_at: string
}

export interface IncidentEvent {
  id: string
  action: string
  from_status: string
  to_status: string
  note: string
  actor_email: string | null
  created_at: string
}

export interface Incident {
  id: string
  alert: string
  alert_code: string
  organization: string | null
  organization_name: string | null
  person: string | null
  person_name: string | null
  device_id: string | null
  latitude: string | null
  longitude: string | null
  location_label: string
  location_area: string
  location_source: string
  location_accuracy_m: number | null
  status: string
  assigned_responder: string | null
  assigned_responder_email: string | null
  acknowledged_at: string | null
  response_started_at: string | null
  resolved_at: string | null
  closed_at: string | null
  resolution: string
  notes: string
  events: IncidentEvent[]
  created_at: string
  updated_at: string
}

export interface TrustedContact {
  id: string
  organization: string | null
  person: string | null
  owner_user: string | null
  name: string
  phone: string
  email: string
  relationship: string
  notify_sms: boolean
  notify_email: boolean
  priority: number
  is_active: boolean
}

export interface SmsMessage {
  id: number
  direction: 'outbound' | 'inbound' | string
  provider: string
  purpose: string
  origin?: string
  source?: string
  phone_number: string
  message: string
  status: string
  provider_message_id: string
  cost: string
  error: string
  user: string | null
  user_email: string | null
  created_at: string
}

export interface SmsStatsBucket {
  key: string
  count: number
  spent: number
}

export interface SmsStats {
  total: number
  outbound: number
  inbound: number
  sent: number
  failed: number
  received: number
  total_spent?: number
  currency?: string
  by_purpose?: SmsStatsBucket[]
  by_provider?: SmsStatsBucket[]
  by_origin?: SmsStatsBucket[]
}

export interface Notification {
  id: string
  channel: string
  recipient: string
  subject: string
  message: string
  status: string
  alert: string | null
  incident: string | null
  created_at: string
  read_at: string | null
}

export interface AuditLog {
  id: string
  actor: string | null
  actor_email: string | null
  action: string
  object_type: string
  object_id: string
  organization: string | null
  ip_address: string | null
  metadata: Record<string, unknown>
  created_at: string
}

export interface DashboardSummary {
  bracelets: { total: number; active: number; unassigned: number; in_use: number }
  people: { total: number }
  alerts: { total: number; last_30_days: number; active: number }
  incidents: {
    open: number
    resolved: number
    total: number
    avg_ack_seconds: number | null
  }
  platform?: { organizations: number; users: number; individuals: number }
  user_growth?: { month: string; label: string; count: number }[]
  alerts_over_time?: { month: string; label: string; count: number }[]
  sms_over_time?: { month: string; label: string; count: number }[]
}

export interface Paginated<T> {
  count: number
  next: string | null
  previous: string | null
  results: T[]
}

export interface ReportSummary {
  totals: {
    alerts: number
    incidents: number
    resolution_rate: number
    avg_ack_seconds: number | null
  }
  alerts_by_date: { date: string | null; count: number }[]
  incidents_by_date: { date: string | null; count: number }[]
  alerts_by_person: { person_id: string; name: string; count: number }[]
  alerts_by_bracelet: { bracelet_id: string; device_id: string; count: number }[]
  alerts_by_code: { alert_code: string; count: number }[]
  device_utilization: { total: number; in_use: number; inactive: number }
}
