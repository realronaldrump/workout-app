import type { Env, OuraDailyDoc, OuraListResponse, OuraWebhookSubscription, OAuthTokenResponse } from "../types"
import { updateConnectionTokens } from "./tokenStore"
import { sleep } from "./utils"

const OURA_API_BASE = "https://api.ouraring.com"
const OURA_AUTH_BASE = "https://cloud.ouraring.com"

export class OuraHttpError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly responseBody: string
  ) {
    super(message)
  }
}

async function parseErrorBody(response: Response): Promise<string> {
  try {
    return await response.text()
  } catch {
    return ""
  }
}

function shouldRetryStatus(status: number): boolean {
  return status === 429 || status >= 500
}

export async function exchangeAuthorizationCode(
  env: Env,
  code: string,
  redirectUri: string
): Promise<OAuthTokenResponse> {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    client_id: env.OURA_CLIENT_ID,
    client_secret: env.OURA_CLIENT_SECRET,
    redirect_uri: redirectUri
  })

  const response = await fetch(`${OURA_API_BASE}/oauth/token`, {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded"
    },
    body
  })

  if (!response.ok) {
    const text = await parseErrorBody(response)
    throw new OuraHttpError("Failed to exchange authorization code", response.status, text)
  }

  return (await response.json()) as OAuthTokenResponse
}

export async function refreshAccessToken(env: Env, refreshToken: string): Promise<OAuthTokenResponse> {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: env.OURA_CLIENT_ID,
    client_secret: env.OURA_CLIENT_SECRET
  })

  const response = await fetch(`${OURA_API_BASE}/oauth/token`, {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded"
    },
    body
  })

  if (!response.ok) {
    const text = await parseErrorBody(response)
    throw new OuraHttpError("Failed to refresh access token", response.status, text)
  }

  return (await response.json()) as OAuthTokenResponse
}

export async function fetchPersonalInfo(accessToken: string): Promise<{ id: string }> {
  const response = await fetch(`${OURA_API_BASE}/v2/usercollection/personal_info`, {
    headers: {
      authorization: `Bearer ${accessToken}`
    }
  })

  if (!response.ok) {
    const text = await parseErrorBody(response)
    throw new OuraHttpError("Failed to fetch personal info", response.status, text)
  }

  const payload = (await response.json()) as { id?: string; data?: { id?: string } }
  const id = payload.id ?? payload.data?.id
  if (!id) {
    throw new Error("Personal info response did not include id")
  }
  return { id }
}

export async function listWebhookSubscriptions(env: Env): Promise<OuraWebhookSubscription[]> {
  const response = await fetch(`${OURA_API_BASE}/v2/webhook/subscription`, {
    headers: {
      "x-client-id": env.OURA_CLIENT_ID,
      "x-client-secret": env.OURA_CLIENT_SECRET
    }
  })

  if (!response.ok) {
    const text = await parseErrorBody(response)
    throw new OuraHttpError("Failed to list webhook subscriptions", response.status, text)
  }

  const payload = (await response.json()) as OuraWebhookSubscription[]
  return Array.isArray(payload) ? payload : []
}

export async function createWebhookSubscription(
  env: Env,
  eventType: "create" | "update" | "delete",
  dataType: string,
  callbackUrl: string,
  verificationToken: string
): Promise<OuraWebhookSubscription> {
  const response = await fetch(`${OURA_API_BASE}/v2/webhook/subscription`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-client-id": env.OURA_CLIENT_ID,
      "x-client-secret": env.OURA_CLIENT_SECRET
    },
    body: JSON.stringify({
      callback_url: callbackUrl,
      verification_token: verificationToken,
      event_type: eventType,
      data_type: dataType
    })
  })

  if (!response.ok) {
    const text = await parseErrorBody(response)
    throw new OuraHttpError("Failed to create webhook subscription", response.status, text)
  }

  return (await response.json()) as OuraWebhookSubscription
}

export async function updateWebhookSubscription(
  env: Env,
  id: string,
  eventType: "create" | "update" | "delete",
  dataType: string,
  callbackUrl: string,
  verificationToken: string
): Promise<OuraWebhookSubscription> {
  const response = await fetch(`${OURA_API_BASE}/v2/webhook/subscription/${encodeURIComponent(id)}`, {
    method: "PUT",
    headers: {
      "content-type": "application/json",
      "x-client-id": env.OURA_CLIENT_ID,
      "x-client-secret": env.OURA_CLIENT_SECRET
    },
    body: JSON.stringify({
      callback_url: callbackUrl,
      verification_token: verificationToken,
      event_type: eventType,
      data_type: dataType
    })
  })

  if (!response.ok) {
    const text = await parseErrorBody(response)
    throw new OuraHttpError("Failed to update webhook subscription", response.status, text)
  }

  return (await response.json()) as OuraWebhookSubscription
}

export async function deleteWebhookSubscription(env: Env, id: string): Promise<void> {
  const response = await fetch(`${OURA_API_BASE}/v2/webhook/subscription/${encodeURIComponent(id)}`, {
    method: "DELETE",
    headers: {
      "x-client-id": env.OURA_CLIENT_ID,
      "x-client-secret": env.OURA_CLIENT_SECRET
    }
  })

  if (!response.ok && response.status !== 404) {
    const text = await parseErrorBody(response)
    throw new OuraHttpError("Failed to delete webhook subscription", response.status, text)
  }
}

export class OuraClient {
  private accessToken: string
  private refreshTokenValue: string

  constructor(
    private readonly env: Env,
    private readonly installId: string,
    accessToken: string,
    refreshToken: string
  ) {
    this.accessToken = accessToken
    this.refreshTokenValue = refreshToken
  }

  async listDailyCollection(
    dataType: "daily_sleep" | "daily_readiness" | "daily_activity",
    startDate: string,
    endDate: string
  ): Promise<OuraDailyDoc[]> {
    const results: OuraDailyDoc[] = []
    let nextToken: string | null = null

    do {
      const params = new URLSearchParams({
        start_date: startDate,
        end_date: endDate
      })
      if (nextToken) {
        params.set("next_token", nextToken)
      }

      const response = await this.requestJson<OuraListResponse<OuraDailyDoc>>(
        `/v2/usercollection/${dataType}?${params.toString()}`
      )

      const pageData = Array.isArray(response.data) ? response.data : []
      results.push(...pageData)
      nextToken = response.next_token ?? null
    } while (nextToken)

    return results
  }

  async fetchSingleDailyDocument(dataType: string, objectId: string): Promise<OuraDailyDoc> {
    return this.requestJson<OuraDailyDoc>(`/v2/usercollection/${dataType}/${encodeURIComponent(objectId)}`)
  }

  private async requestJson<T>(path: string, method = "GET", body?: unknown): Promise<T> {
    const headers = new Headers({
      authorization: `Bearer ${this.accessToken}`,
      "content-type": "application/json"
    })

    return this.requestWithRetry<T>(path, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body)
    })
  }

  private async requestWithRetry<T>(
    path: string,
    init: RequestInit,
    attempt = 0,
    hasRefreshed = false
  ): Promise<T> {
    const response = await fetch(`${OURA_API_BASE}${path}`, init)

    if (response.status === 401 && !hasRefreshed) {
      await this.refreshAccessToken()
      const retryHeaders = new Headers(init.headers)
      retryHeaders.set("authorization", `Bearer ${this.accessToken}`)
      return this.requestWithRetry<T>(path, { ...init, headers: retryHeaders }, attempt, true)
    }

    if (shouldRetryStatus(response.status) && attempt < 5) {
      const jitter = Math.floor(Math.random() * 250)
      const backoffMs = 500 * 2 ** attempt + jitter
      await sleep(backoffMs)
      return this.requestWithRetry(path, init, attempt + 1, hasRefreshed)
    }

    if (!response.ok) {
      const text = await parseErrorBody(response)
      throw new OuraHttpError(`Oura request failed: ${path}`, response.status, text)
    }

    return (await response.json()) as T
  }

  private async refreshAccessToken(): Promise<void> {
    const refreshed = await refreshAccessToken(this.env, this.refreshTokenValue)
    this.accessToken = refreshed.access_token
    this.refreshTokenValue = refreshed.refresh_token
    await updateConnectionTokens(this.env, this.installId, refreshed)
  }
}

export function buildAuthorizeUrl(env: Env, state: string, redirectUri: string): string {
  const params = new URLSearchParams({
    client_id: env.OURA_CLIENT_ID,
    redirect_uri: redirectUri,
    response_type: "code",
    scope: "daily personal",
    state
  })
  return `${OURA_AUTH_BASE}/oauth/authorize?${params.toString()}`
}
