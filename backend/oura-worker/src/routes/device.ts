import type { Env } from "../types"
import { errorResponse, jsonResponse, nowIso, randomId, randomToken, sha256Hex } from "../lib/utils"

export async function registerDevice(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") {
    return errorResponse(405, "Method not allowed")
  }

  const installId = randomId("install")
  const installToken = randomToken(48)
  const tokenHash = await sha256Hex(installToken)
  const now = nowIso()

  await env.DB.prepare(
    `INSERT INTO installations (
       id,
       token_hash,
       status,
       created_at,
       last_seen_at
     ) VALUES (?, ?, 'registered', ?, ?)`
  )
    .bind(installId, tokenHash, now, now)
    .run()

  return jsonResponse(
    {
      install_id: installId,
      install_token: installToken
    },
    201
  )
}
