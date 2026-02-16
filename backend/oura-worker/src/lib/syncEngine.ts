import type { Env, OuraDailyDoc, OuraWebhookSubscription, SyncMode } from "../types"
import {
  createWebhookSubscription,
  deleteWebhookSubscription,
  listWebhookSubscriptions,
  OuraClient,
  OuraHttpError,
  updateWebhookSubscription
} from "./ouraClient"
import { getDecryptedConnection, markConnectionStale, touchSyncSuccess } from "./tokenStore"
import { addDays, formatDateOnly, nowIso, randomId } from "./utils"

const SUPPORTED_DAILY_TYPES = new Set(["daily_sleep", "daily_readiness", "daily_activity"])
const WEBHOOK_DATA_TYPES: Array<"daily_sleep" | "daily_readiness" | "daily_activity"> = [
  "daily_sleep",
  "daily_readiness",
  "daily_activity"
]
const WEBHOOK_EVENT_TYPES: Array<"create" | "update"> = ["create", "update"]

export async function ensureWebhookSubscriptions(env: Env): Promise<void> {
  const callbackUrl = `${env.PUBLIC_BASE_URL.replace(/\/$/, "")}/v1/webhooks/oura`
  const existing = await listWebhookSubscriptions(env)

  for (const eventType of WEBHOOK_EVENT_TYPES) {
    for (const dataType of WEBHOOK_DATA_TYPES) {
      const match = existing.find((item) => item.event_type === eventType && item.data_type === dataType)
      if (match) {
        await upsertWebhookSubscriptionRow(env, match)
        continue
      }

      const created = await createWebhookSubscription(
        env,
        eventType,
        dataType,
        callbackUrl,
        env.OURA_VERIFICATION_TOKEN
      )
      await upsertWebhookSubscriptionRow(env, created)
    }
  }
}

export async function renewExpiringWebhookSubscriptions(env: Env): Promise<void> {
  const callbackUrl = `${env.PUBLIC_BASE_URL.replace(/\/$/, "")}/v1/webhooks/oura`
  const existing = await listWebhookSubscriptions(env)
  const now = Date.now()
  const thresholdMs = now + 3 * 86_400_000

  for (const subscription of existing) {
    if (!subscription.expiration_time) {
      await upsertWebhookSubscriptionRow(env, subscription)
      continue
    }

    const expirationMs = Date.parse(subscription.expiration_time)
    if (Number.isNaN(expirationMs) || expirationMs > thresholdMs) {
      await upsertWebhookSubscriptionRow(env, subscription)
      continue
    }

    const renewed = await updateWebhookSubscription(
      env,
      subscription.id,
      subscription.event_type,
      subscription.data_type,
      callbackUrl,
      env.OURA_VERIFICATION_TOKEN
    )
    await upsertWebhookSubscriptionRow(env, renewed)
  }
}

export async function deleteAllWebhookSubscriptions(env: Env): Promise<void> {
  const rows = await env.DB.prepare(`SELECT id FROM oura_webhook_subscriptions WHERE active = 1`).all<{ id: string }>()
  const ids = rows.results.map((row) => row.id)

  for (const id of ids) {
    await deleteWebhookSubscription(env, id)
  }

  await env.DB.prepare(`DELETE FROM oura_webhook_subscriptions`).run()
}

export async function syncDailyRange(
  env: Env,
  installId: string,
  startDate: string,
  endDate: string,
  mode: SyncMode,
  syncRunId?: string
): Promise<void> {
  const runId = syncRunId ?? randomId("sync")
  const startedAt = nowIso()
  await createSyncRun(env, runId, installId, mode, startedAt)

  const connection = await getDecryptedConnection(env, installId)
  if (!connection) {
    await failSyncRun(env, runId, "No Oura connection found for install")
    return
  }

  const client = new OuraClient(env, installId, connection.accessToken, connection.refreshToken)
  let recordsWritten = 0

  try {
    for (const dataType of WEBHOOK_DATA_TYPES) {
      const docs = await client.listDailyCollection(dataType, startDate, endDate)
      for (const doc of docs) {
        const didWrite = await upsertDailyDoc(env, installId, dataType, doc)
        if (didWrite) {
          recordsWritten += 1
        }
      }
    }

    await touchSyncSuccess(env, installId)
    await completeSyncRun(env, runId, recordsWritten)
  } catch (error) {
    const message = extractErrorMessage(error)
    if (error instanceof OuraHttpError && (error.status === 401 || error.status === 403)) {
      await markConnectionStale(env, installId, message)
    } else {
      await env.DB.prepare(`UPDATE installations SET last_error = ? WHERE id = ?`).bind(message, installId).run()
    }
    await failSyncRun(env, runId, message, recordsWritten)
    throw error
  }
}

export async function processWebhookEvent(
  env: Env,
  installId: string,
  eventType: "create" | "update" | "delete",
  dataType: string,
  objectId: string
): Promise<void> {
  if (!SUPPORTED_DAILY_TYPES.has(dataType)) {
    return
  }

  if (eventType === "delete") {
    const end = new Date()
    const start = addDays(end, -14)
    await syncDailyRange(env, installId, formatDateOnly(start), formatDateOnly(end), "webhook")
    return
  }

  const connection = await getDecryptedConnection(env, installId)
  if (!connection) {
    return
  }

  const client = new OuraClient(env, installId, connection.accessToken, connection.refreshToken)
  const doc = await client.fetchSingleDailyDocument(dataType, objectId)
  await upsertDailyDoc(env, installId, dataType, doc)
  await touchSyncSuccess(env, installId)
}

async function createSyncRun(
  env: Env,
  runId: string,
  installId: string,
  mode: SyncMode,
  startedAt: string
): Promise<void> {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO sync_runs (id, install_id, mode, status, started_at, records_written)
     VALUES (?, ?, ?, 'running', ?, 0)`
  )
    .bind(runId, installId, mode, startedAt)
    .run()
}

async function completeSyncRun(env: Env, runId: string, recordsWritten: number): Promise<void> {
  await env.DB.prepare(
    `UPDATE sync_runs
     SET status = 'completed',
         finished_at = ?,
         records_written = ?
     WHERE id = ?`
  )
    .bind(nowIso(), recordsWritten, runId)
    .run()
}

async function failSyncRun(env: Env, runId: string, errorSummary: string, recordsWritten = 0): Promise<void> {
  await env.DB.prepare(
    `UPDATE sync_runs
     SET status = 'failed',
         finished_at = ?,
         records_written = ?,
         error_summary = ?
     WHERE id = ?`
  )
    .bind(nowIso(), recordsWritten, errorSummary.slice(0, 2000), runId)
    .run()
}

async function upsertDailyDoc(
  env: Env,
  installId: string,
  dataType: "daily_sleep" | "daily_readiness" | "daily_activity" | string,
  doc: OuraDailyDoc
): Promise<boolean> {
  const day = typeof doc.day === "string" ? doc.day : null
  if (!day) {
    return false
  }

  const timestamp = typeof doc.timestamp === "string" ? doc.timestamp : null
  const score = typeof doc.score === "number" ? doc.score : null
  const contributors =
    doc.contributors && typeof doc.contributors === "object" ? JSON.stringify(doc.contributors) : null

  const updatedAt = nowIso()

  if (dataType === "daily_sleep") {
    await env.DB.prepare(
      `INSERT INTO oura_daily_scores (
         install_id,
         day,
         sleep_score,
         sleep_contributors_json,
         sleep_timestamp,
         updated_at
       ) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(install_id, day) DO UPDATE SET
         sleep_score = excluded.sleep_score,
         sleep_contributors_json = excluded.sleep_contributors_json,
         sleep_timestamp = excluded.sleep_timestamp,
         updated_at = excluded.updated_at`
    )
      .bind(installId, day, score, contributors, timestamp, updatedAt)
      .run()
  } else if (dataType === "daily_readiness") {
    await env.DB.prepare(
      `INSERT INTO oura_daily_scores (
         install_id,
         day,
         readiness_score,
         readiness_contributors_json,
         readiness_timestamp,
         updated_at
       ) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(install_id, day) DO UPDATE SET
         readiness_score = excluded.readiness_score,
         readiness_contributors_json = excluded.readiness_contributors_json,
         readiness_timestamp = excluded.readiness_timestamp,
         updated_at = excluded.updated_at`
    )
      .bind(installId, day, score, contributors, timestamp, updatedAt)
      .run()
  } else if (dataType === "daily_activity") {
    await env.DB.prepare(
      `INSERT INTO oura_daily_scores (
         install_id,
         day,
         activity_score,
         activity_contributors_json,
         activity_timestamp,
         updated_at
       ) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(install_id, day) DO UPDATE SET
         activity_score = excluded.activity_score,
         activity_contributors_json = excluded.activity_contributors_json,
         activity_timestamp = excluded.activity_timestamp,
         updated_at = excluded.updated_at`
    )
      .bind(installId, day, score, contributors, timestamp, updatedAt)
      .run()
  } else {
    return false
  }

  const rawKey = `${installId}/${day}/${dataType}.json`
  await env.RAW_BUCKET.put(rawKey, JSON.stringify(doc), {
    httpMetadata: {
      contentType: "application/json"
    }
  })

  return true
}

function extractErrorMessage(error: unknown): string {
  if (error instanceof OuraHttpError) {
    const body = error.responseBody ? ` (${error.responseBody})` : ""
    return `${error.message}: HTTP ${error.status}${body}`
  }
  if (error instanceof Error) {
    return error.message
  }
  return String(error)
}

async function upsertWebhookSubscriptionRow(env: Env, sub: OuraWebhookSubscription): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO oura_webhook_subscriptions (
       id,
       install_id,
       event_type,
       data_type,
       callback_url,
       expiration_time,
       active
     ) VALUES (?, NULL, ?, ?, ?, ?, 1)
     ON CONFLICT(id) DO UPDATE SET
       event_type = excluded.event_type,
       data_type = excluded.data_type,
       callback_url = excluded.callback_url,
       expiration_time = excluded.expiration_time,
       active = 1`
  )
    .bind(sub.id, sub.event_type, sub.data_type, sub.callback_url, sub.expiration_time ?? null)
    .run()
}
