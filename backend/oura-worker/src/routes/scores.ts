import type { Env } from "../types"
import { requireInstallAuth } from "../lib/auth"
import { deleteAllWebhookSubscriptions, syncDailyRange } from "../lib/syncEngine"
import { ensureDateRange, errorResponse, formatDateOnly, jsonResponse } from "../lib/utils"

type ScoreRow = {
  day: string
  sleep_score: number | null
  readiness_score: number | null
  activity_score: number | null
  sleep_contributors_json: string | null
  readiness_contributors_json: string | null
  activity_contributors_json: string | null
  sleep_timestamp: string | null
  readiness_timestamp: string | null
  activity_timestamp: string | null
  updated_at: string
}

function parseMaybeJson(value: string | null): Record<string, number> | null {
  if (!value) {
    return null
  }
  try {
    return JSON.parse(value) as Record<string, number>
  } catch {
    return null
  }
}

export async function getScores(request: Request, env: Env): Promise<Response> {
  if (request.method !== "GET") {
    return errorResponse(405, "Method not allowed")
  }

  const auth = await requireInstallAuth(request, env)
  if (auth instanceof Response) {
    return auth
  }

  const url = new URL(request.url)
  const { startDate, endDate } = ensureDateRange(url)
  const rows = await env.DB.prepare(
    `SELECT
       day,
       sleep_score,
       readiness_score,
       activity_score,
       sleep_contributors_json,
       readiness_contributors_json,
       activity_contributors_json,
       sleep_timestamp,
       readiness_timestamp,
       activity_timestamp,
       updated_at
     FROM oura_daily_scores
     WHERE install_id = ?
       AND day >= ?
       AND day <= ?
     ORDER BY day ASC`
  )
    .bind(auth.install.id, startDate, endDate)
    .all<ScoreRow>()

  const data = rows.results.map((row) => ({
    day: row.day,
    sleep_score: row.sleep_score,
    readiness_score: row.readiness_score,
    activity_score: row.activity_score,
    sleep_contributors: parseMaybeJson(row.sleep_contributors_json),
    readiness_contributors: parseMaybeJson(row.readiness_contributors_json),
    activity_contributors: parseMaybeJson(row.activity_contributors_json),
    sleep_timestamp: row.sleep_timestamp,
    readiness_timestamp: row.readiness_timestamp,
    activity_timestamp: row.activity_timestamp,
    updated_at: row.updated_at
  }))

  return jsonResponse({ data })
}

export async function triggerSync(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") {
    return errorResponse(405, "Method not allowed")
  }

  const auth = await requireInstallAuth(request, env)
  if (auth instanceof Response) {
    return auth
  }

  const url = new URL(request.url)
  const body = request.headers.get("content-type")?.includes("application/json") ? await request.json().catch(() => ({})) : {}
  const startDate = typeof (body as Record<string, unknown>).start_date === "string"
    ? (body as Record<string, string>).start_date
    : url.searchParams.get("start_date") ?? formatDateOnly(new Date(Date.now() - 30 * 86_400_000))
  const endDate = typeof (body as Record<string, unknown>).end_date === "string"
    ? (body as Record<string, string>).end_date
    : url.searchParams.get("end_date") ?? formatDateOnly(new Date())

  await env.OURA_SYNC_QUEUE.send({
    type: "sync_range",
    installId: auth.install.id,
    startDate,
    endDate,
    mode: "delta"
  })

  return jsonResponse({ accepted: true, start_date: startDate, end_date: endDate }, 202)
}

export async function deleteConnection(request: Request, env: Env): Promise<Response> {
  if (request.method !== "DELETE") {
    return errorResponse(405, "Method not allowed")
  }

  const auth = await requireInstallAuth(request, env)
  if (auth instanceof Response) {
    return auth
  }

  const installId = auth.install.id

  await env.DB.prepare(`DELETE FROM oura_connections WHERE install_id = ?`).bind(installId).run()
  await env.DB.prepare(`DELETE FROM oura_daily_scores WHERE install_id = ?`).bind(installId).run()
  await env.DB.prepare(`DELETE FROM sync_runs WHERE install_id = ?`).bind(installId).run()
  await env.DB.prepare(
    `UPDATE installations
     SET status = 'registered',
         oauth_state = NULL,
         oauth_state_expires_at = NULL,
         last_error = NULL,
         last_sync_at = NULL
     WHERE id = ?`
  )
    .bind(installId)
    .run()

  await deleteRawSnapshots(env, installId)

  const connectionCount = await env.DB.prepare(`SELECT COUNT(*) AS count FROM oura_connections`).first<{ count: number }>()
  if ((connectionCount?.count ?? 0) === 0) {
    await deleteAllWebhookSubscriptions(env)
  }

  return new Response(null, { status: 204 })
}

async function deleteRawSnapshots(env: Env, installId: string): Promise<void> {
  let cursor: string | undefined

  do {
    const listed = await env.RAW_BUCKET.list({ prefix: `${installId}/`, cursor })
    if (listed.objects.length > 0) {
      await env.RAW_BUCKET.delete(listed.objects.map((obj) => obj.key))
    }
    cursor = listed.truncated ? listed.cursor : undefined
  } while (cursor)
}

export async function localBackfillForInstall(env: Env, installId: string): Promise<void> {
  await syncDailyRange(env, installId, "2015-01-01", formatDateOnly(new Date()), "backfill")
}
