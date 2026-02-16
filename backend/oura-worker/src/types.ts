export interface Env {
  DB: D1Database
  RAW_BUCKET: R2Bucket
  OURA_SYNC_QUEUE: Queue<SyncQueueMessage>
  OURA_CLIENT_ID: string
  OURA_CLIENT_SECRET: string
  TOKEN_ENCRYPTION_KEY: string
  OURA_VERIFICATION_TOKEN: string
  PUBLIC_BASE_URL: string
  APP_CALLBACK_URL: string
  FEATURE_OURA_ENABLED?: string
}

export interface InstallationRow {
  id: string
  token_hash: string
  status: string
  oauth_state: string | null
  oauth_state_expires_at: string | null
  last_error: string | null
  last_sync_at: string | null
  created_at: string
  last_seen_at: string
}

export interface OuraConnectionRow {
  install_id: string
  oura_user_id: string
  access_token_encrypted: string
  refresh_token_encrypted: string
  scopes: string | null
  token_expires_at: string | null
  connected_at: string
  stale: number
}

export interface AuthContext {
  install: InstallationRow
  installToken: string
}

export type SyncMode = "backfill" | "delta" | "webhook"

export type SyncQueueMessage =
  | {
      type: "sync_range"
      installId: string
      startDate: string
      endDate: string
      mode: SyncMode
      syncRunId?: string
    }
  | {
      type: "webhook_event"
      installId: string
      eventType: "create" | "update" | "delete"
      dataType: string
      objectId: string
      eventTime?: string
    }

export interface OAuthTokenResponse {
  access_token: string
  refresh_token: string
  expires_in?: number
  token_type?: string
  scope?: string
}

export interface OuraDailyDoc {
  id: string
  day: string
  score?: number
  timestamp?: string
  contributors?: Record<string, number>
  [key: string]: unknown
}

export interface OuraListResponse<T> {
  data: T[]
  next_token?: string
}

export interface OuraWebhookSubscription {
  id: string
  callback_url: string
  event_type: "create" | "update" | "delete"
  data_type: string
  expiration_time?: string
}
