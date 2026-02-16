import type { AuthContext, Env, InstallationRow } from "../types"
import { errorResponse, nowIso, sha256Hex } from "./utils"

function extractBearerToken(request: Request): string | null {
  const header = request.headers.get("authorization")
  if (!header) {
    return null
  }
  const [scheme, token] = header.split(" ")
  if (!scheme || !token || scheme.toLowerCase() !== "bearer") {
    return null
  }
  return token.trim()
}

export async function requireInstallAuth(request: Request, env: Env): Promise<AuthContext | Response> {
  const installToken = extractBearerToken(request)
  if (!installToken) {
    return errorResponse(401, "Missing or invalid bearer token")
  }

  const tokenHash = await sha256Hex(installToken)
  const row = await env.DB.prepare(
    `SELECT id, token_hash, status, oauth_state, oauth_state_expires_at, last_error, last_sync_at, created_at, last_seen_at
     FROM installations
     WHERE token_hash = ?`
  )
    .bind(tokenHash)
    .first<InstallationRow>()

  if (!row) {
    return errorResponse(401, "Unknown install token")
  }

  await env.DB.prepare(`UPDATE installations SET last_seen_at = ? WHERE id = ?`)
    .bind(nowIso(), row.id)
    .run()

  return {
    install: row,
    installToken
  }
}
