import type { Env } from "../types"
import { computeWebhookSignatureHexUpper } from "../lib/crypto"
import { errorResponse, jsonResponse } from "../lib/utils"

interface IncomingWebhookPayload {
  event_type: "create" | "update" | "delete"
  data_type: string
  object_id: string
  event_time?: string
  user_id: string
}

export async function handleWebhookVerification(request: Request, env: Env): Promise<Response> {
  if (request.method !== "GET") {
    return errorResponse(405, "Method not allowed")
  }

  const url = new URL(request.url)
  const verificationToken = url.searchParams.get("verification_token")
  const challenge = url.searchParams.get("challenge")

  if (!verificationToken || verificationToken !== env.OURA_VERIFICATION_TOKEN || !challenge) {
    return errorResponse(401, "Invalid verification request")
  }

  return jsonResponse({ challenge })
}

export async function handleWebhookEvent(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") {
    return errorResponse(405, "Method not allowed")
  }

  const timestamp = request.headers.get("x-oura-timestamp")
  const signature = request.headers.get("x-oura-signature")
  if (!timestamp || !signature) {
    return errorResponse(401, "Missing signature headers")
  }

  const rawBody = await request.text()
  const expectedSignature = await computeWebhookSignatureHexUpper(env.OURA_CLIENT_SECRET, timestamp, rawBody)
  if (expectedSignature !== signature) {
    return errorResponse(401, "Invalid webhook signature")
  }

  let payload: IncomingWebhookPayload
  try {
    payload = JSON.parse(rawBody) as IncomingWebhookPayload
  } catch {
    return errorResponse(400, "Invalid webhook JSON")
  }

  if (!payload.user_id || !payload.object_id || !payload.data_type || !payload.event_type) {
    return errorResponse(422, "Webhook payload missing required fields")
  }

  const row = await env.DB.prepare(`SELECT install_id FROM oura_connections WHERE oura_user_id = ?`)
    .bind(payload.user_id)
    .first<{ install_id: string }>()

  if (!row?.install_id) {
    return new Response("OK", { status: 202 })
  }

  await env.OURA_SYNC_QUEUE.send({
    type: "webhook_event",
    installId: row.install_id,
    eventType: payload.event_type,
    dataType: payload.data_type,
    objectId: payload.object_id,
    eventTime: payload.event_time
  })

  return new Response("OK", { status: 200 })
}
