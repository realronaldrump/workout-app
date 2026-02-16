import type { AuthContext, Env } from "../types"
import { requireInstallAuth } from "../lib/auth"
import { buildAuthorizeUrl, exchangeAuthorizationCode, fetchPersonalInfo } from "../lib/ouraClient"
import { ensureWebhookSubscriptions } from "../lib/syncEngine"
import { upsertConnection } from "../lib/tokenStore"
import { addMinutes, appendQuery, errorResponse, formatDateOnly, jsonResponse, nowIso, randomId } from "../lib/utils"

function callbackRedirect(responseUrl: string): Response {
  const html = `<!DOCTYPE html>
<html>
<head><meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" /></head>
<body>
  <p>Returning to app…</p>
  <script>window.location.href = ${JSON.stringify(responseUrl)};</script>
</body>
</html>`

  return new Response(html, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8"
    }
  })
}

export async function getConnectUrl(request: Request, env: Env): Promise<Response> {
  if (request.method !== "GET") {
    return errorResponse(405, "Method not allowed")
  }

  const auth = await requireInstallAuth(request, env)
  if (auth instanceof Response) {
    return auth
  }

  const state = randomId("state")
  const expiresAt = addMinutes(new Date(), 10).toISOString()

  await env.DB.prepare(
    `UPDATE installations
     SET oauth_state = ?, oauth_state_expires_at = ?, status = 'connecting', last_error = NULL
     WHERE id = ?`
  )
    .bind(state, expiresAt, auth.install.id)
    .run()

  const redirectUri = `${env.PUBLIC_BASE_URL.replace(/\/$/, "")}/v1/oura/oauth/callback`
  const url = buildAuthorizeUrl(env, state, redirectUri)
  return jsonResponse({ url, state })
}

export async function handleOAuthCallback(request: Request, env: Env): Promise<Response> {
  if (request.method !== "GET") {
    return errorResponse(405, "Method not allowed")
  }

  const url = new URL(request.url)
  const state = url.searchParams.get("state")
  const code = url.searchParams.get("code")
  const oauthError = url.searchParams.get("error")
  const callbackBase = env.APP_CALLBACK_URL

  if (!state) {
    return callbackRedirect(appendQuery(callbackBase, { status: "error", reason: "missing_state" }))
  }

  const installation = await env.DB.prepare(
    `SELECT id, oauth_state_expires_at
     FROM installations
     WHERE oauth_state = ?`
  )
    .bind(state)
    .first<{ id: string; oauth_state_expires_at: string | null }>()

  if (!installation) {
    return callbackRedirect(appendQuery(callbackBase, { status: "error", reason: "unknown_state" }))
  }

  if (!installation.oauth_state_expires_at || Date.parse(installation.oauth_state_expires_at) < Date.now()) {
    await env.DB.prepare(`UPDATE installations SET oauth_state = NULL, oauth_state_expires_at = NULL, status = 'error', last_error = ? WHERE id = ?`)
      .bind("OAuth state expired", installation.id)
      .run()
    return callbackRedirect(appendQuery(callbackBase, { status: "error", reason: "state_expired" }))
  }

  if (oauthError) {
    await env.DB.prepare(`UPDATE installations SET oauth_state = NULL, oauth_state_expires_at = NULL, status = 'error', last_error = ? WHERE id = ?`)
      .bind(`OAuth error: ${oauthError}`, installation.id)
      .run()
    return callbackRedirect(appendQuery(callbackBase, { status: "error", reason: oauthError }))
  }

  if (!code) {
    return callbackRedirect(appendQuery(callbackBase, { status: "error", reason: "missing_code" }))
  }

  try {
    const redirectUri = `${env.PUBLIC_BASE_URL.replace(/\/$/, "")}/v1/oura/oauth/callback`
    const tokenResponse = await exchangeAuthorizationCode(env, code, redirectUri)
    const personal = await fetchPersonalInfo(tokenResponse.access_token)

    await upsertConnection(env, installation.id, personal.id, tokenResponse)
    await env.DB.prepare(
      `UPDATE installations
       SET oauth_state = NULL,
           oauth_state_expires_at = NULL,
           status = 'connected',
           last_error = NULL,
           last_seen_at = ?
       WHERE id = ?`
    )
      .bind(nowIso(), installation.id)
      .run()

    await ensureWebhookSubscriptions(env)

    await env.OURA_SYNC_QUEUE.send({
      type: "sync_range",
      installId: installation.id,
      startDate: "2015-01-01",
      endDate: formatDateOnly(new Date()),
      mode: "backfill"
    })

    return callbackRedirect(
      appendQuery(callbackBase, {
        status: "success",
        install_id: installation.id
      })
    )
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    await env.DB.prepare(
      `UPDATE installations
       SET oauth_state = NULL,
           oauth_state_expires_at = NULL,
           status = 'error',
           last_error = ?
       WHERE id = ?`
    )
      .bind(message, installation.id)
      .run()

    return callbackRedirect(appendQuery(callbackBase, { status: "error", reason: "oauth_exchange_failed" }))
  }
}

export async function getStatus(request: Request, env: Env): Promise<Response> {
  if (request.method !== "GET") {
    return errorResponse(405, "Method not allowed")
  }

  const auth = await requireInstallAuth(request, env)
  if (auth instanceof Response) {
    return auth
  }

  const row = await env.DB.prepare(
    `SELECT
       i.status AS install_status,
       i.last_sync_at,
       i.last_error,
       c.install_id AS connected_install,
       c.stale,
       c.connected_at
     FROM installations i
     LEFT JOIN oura_connections c ON c.install_id = i.id
     WHERE i.id = ?`
  )
    .bind(auth.install.id)
    .first<{
      install_status: string
      last_sync_at: string | null
      last_error: string | null
      connected_install: string | null
      stale: number | null
      connected_at: string | null
    }>()

  const isConnected = Boolean(row?.connected_install)
  const stale = row?.stale === 1

  return jsonResponse({
    connected: isConnected,
    stale,
    status: isConnected ? (stale ? "error" : "connected") : "not_connected",
    connected_at: row?.connected_at ?? null,
    last_sync_at: row?.last_sync_at ?? null,
    last_error: row?.last_error ?? null
  })
}

export async function requireAuthContext(request: Request, env: Env): Promise<AuthContext | Response> {
  return requireInstallAuth(request, env)
}

// imported by index.ts to keep route ownership clear
export const oauthRoutes = {
  getConnectUrl,
  handleOAuthCallback,
  getStatus
}
