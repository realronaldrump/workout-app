import type { Env, OuraConnectionRow, OAuthTokenResponse } from "../types"
import { decryptSecret, encryptSecret } from "./crypto"
import { nowIso } from "./utils"

export interface DecryptedConnection {
  installId: string
  ouraUserId: string
  accessToken: string
  refreshToken: string
  scopes: string | null
  tokenExpiresAt: string | null
  stale: boolean
}

export async function getDecryptedConnection(env: Env, installId: string): Promise<DecryptedConnection | null> {
  const row = await env.DB.prepare(
    `SELECT install_id, oura_user_id, access_token_encrypted, refresh_token_encrypted, scopes, token_expires_at, connected_at, stale
     FROM oura_connections
     WHERE install_id = ?`
  )
    .bind(installId)
    .first<OuraConnectionRow>()

  if (!row) {
    return null
  }

  const accessToken = await decryptSecret(row.access_token_encrypted, env.TOKEN_ENCRYPTION_KEY)
  const refreshToken = await decryptSecret(row.refresh_token_encrypted, env.TOKEN_ENCRYPTION_KEY)

  return {
    installId: row.install_id,
    ouraUserId: row.oura_user_id,
    accessToken,
    refreshToken,
    scopes: row.scopes,
    tokenExpiresAt: row.token_expires_at,
    stale: row.stale === 1
  }
}

export async function upsertConnection(
  env: Env,
  installId: string,
  ouraUserId: string,
  tokenResponse: OAuthTokenResponse
): Promise<void> {
  const now = new Date()
  const expiresAt = tokenResponse.expires_in
    ? new Date(now.getTime() + tokenResponse.expires_in * 1000).toISOString()
    : null

  const encryptedAccess = await encryptSecret(tokenResponse.access_token, env.TOKEN_ENCRYPTION_KEY)
  const encryptedRefresh = await encryptSecret(tokenResponse.refresh_token, env.TOKEN_ENCRYPTION_KEY)

  await env.DB.prepare(
    `INSERT INTO oura_connections (
      install_id,
      oura_user_id,
      access_token_encrypted,
      refresh_token_encrypted,
      scopes,
      token_expires_at,
      connected_at,
      stale
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0)
    ON CONFLICT(install_id) DO UPDATE SET
      oura_user_id = excluded.oura_user_id,
      access_token_encrypted = excluded.access_token_encrypted,
      refresh_token_encrypted = excluded.refresh_token_encrypted,
      scopes = excluded.scopes,
      token_expires_at = excluded.token_expires_at,
      connected_at = excluded.connected_at,
      stale = 0`
  )
    .bind(
      installId,
      ouraUserId,
      encryptedAccess,
      encryptedRefresh,
      tokenResponse.scope ?? null,
      expiresAt,
      now.toISOString()
    )
    .run()

  await env.DB.prepare(`UPDATE installations SET status = 'connected', last_error = NULL WHERE id = ?`)
    .bind(installId)
    .run()
}

export async function markConnectionStale(env: Env, installId: string, message: string): Promise<void> {
  await env.DB.prepare(`UPDATE oura_connections SET stale = 1 WHERE install_id = ?`)
    .bind(installId)
    .run()

  await env.DB.prepare(`UPDATE installations SET status = 'error', last_error = ? WHERE id = ?`)
    .bind(message, installId)
    .run()
}

export async function updateConnectionTokens(
  env: Env,
  installId: string,
  tokenResponse: OAuthTokenResponse
): Promise<void> {
  const now = new Date()
  const expiresAt = tokenResponse.expires_in
    ? new Date(now.getTime() + tokenResponse.expires_in * 1000).toISOString()
    : null
  const accessEncrypted = await encryptSecret(tokenResponse.access_token, env.TOKEN_ENCRYPTION_KEY)
  const refreshEncrypted = await encryptSecret(tokenResponse.refresh_token, env.TOKEN_ENCRYPTION_KEY)

  await env.DB.prepare(
    `UPDATE oura_connections
     SET access_token_encrypted = ?,
         refresh_token_encrypted = ?,
         token_expires_at = ?,
         scopes = COALESCE(?, scopes),
         stale = 0
     WHERE install_id = ?`
  )
    .bind(accessEncrypted, refreshEncrypted, expiresAt, tokenResponse.scope ?? null, installId)
    .run()
}

export async function touchSyncSuccess(env: Env, installId: string): Promise<void> {
  const now = nowIso()
  await env.DB.prepare(`UPDATE installations SET status = 'connected', last_sync_at = ?, last_error = NULL WHERE id = ?`)
    .bind(now, installId)
    .run()
}
