import type { Env, SyncQueueMessage } from "./types"
import { registerDevice } from "./routes/device"
import { oauthRoutes } from "./routes/oauth"
import { deleteConnection, getScores, triggerSync } from "./routes/scores"
import { handleWebhookEvent, handleWebhookVerification } from "./routes/webhooks"
import { ensureWebhookSubscriptions, processWebhookEvent, renewExpiringWebhookSubscriptions, syncDailyRange } from "./lib/syncEngine"
import { errorResponse, isFeatureEnabled } from "./lib/utils"

async function routeRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url)
  const { pathname } = url

  if (pathname === "/v1/device/register") {
    return registerDevice(request, env)
  }

  if (!isFeatureEnabled(env)) {
    return errorResponse(503, "Oura integration disabled")
  }

  if (pathname === "/v1/oura/connect-url") {
    return oauthRoutes.getConnectUrl(request, env)
  }

  if (pathname === "/v1/oura/oauth/callback") {
    return oauthRoutes.handleOAuthCallback(request, env)
  }

  if (pathname === "/v1/oura/status") {
    return oauthRoutes.getStatus(request, env)
  }

  if (pathname === "/v1/oura/scores") {
    return getScores(request, env)
  }

  if (pathname === "/v1/oura/sync") {
    return triggerSync(request, env)
  }

  if (pathname === "/v1/oura/connection") {
    return deleteConnection(request, env)
  }

  if (pathname === "/v1/webhooks/oura" && request.method === "GET") {
    return handleWebhookVerification(request, env)
  }

  if (pathname === "/v1/webhooks/oura" && request.method === "POST") {
    return handleWebhookEvent(request, env)
  }

  return errorResponse(404, "Not found")
}

async function handleQueueMessage(env: Env, message: SyncQueueMessage): Promise<void> {
  if (message.type === "sync_range") {
    await syncDailyRange(env, message.installId, message.startDate, message.endDate, message.mode, message.syncRunId)
    return
  }

  if (message.type === "webhook_event") {
    await processWebhookEvent(env, message.installId, message.eventType, message.dataType, message.objectId)
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await routeRequest(request, env)
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error)
      return errorResponse(500, "Unhandled server error", message)
    }
  },

  async queue(batch: MessageBatch<SyncQueueMessage>, env: Env): Promise<void> {
    for (const message of batch.messages) {
      try {
        await handleQueueMessage(env, message.body)
        message.ack()
      } catch (error) {
        console.error("Queue message failed", error)
        message.retry()
      }
    }
  },

  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    try {
      await ensureWebhookSubscriptions(env)
      await renewExpiringWebhookSubscriptions(env)
    } catch (error) {
      console.error("Scheduled maintenance failed", error)
    }
  }
}
