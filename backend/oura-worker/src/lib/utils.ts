import type { Env } from "../types"

export function isFeatureEnabled(env: Env): boolean {
  return (env.FEATURE_OURA_ENABLED ?? "true").toLowerCase() === "true"
}

export function jsonResponse(data: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...headers
    }
  })
}

export function errorResponse(status: number, error: string, details?: unknown): Response {
  const body: Record<string, unknown> = { error }
  if (details !== undefined) {
    body.details = details
  }
  return jsonResponse(body, status)
}

export function nowIso(): string {
  return new Date().toISOString()
}

export function randomId(prefix?: string): string {
  const raw = crypto.randomUUID()
  return prefix ? `${prefix}_${raw}` : raw
}

export function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60_000)
}

export function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 86_400_000)
}

export function formatDateOnly(date: Date): string {
  return date.toISOString().slice(0, 10)
}

export function parseDateOnly(value: string | null, fallback: Date): Date {
  if (!value) {
    return fallback
  }
  const parsed = new Date(`${value}T00:00:00.000Z`)
  if (Number.isNaN(parsed.getTime())) {
    return fallback
  }
  return parsed
}

export function ensureDateRange(url: URL): { startDate: string; endDate: string } {
  const today = formatDateOnly(new Date())
  const defaultStart = formatDateOnly(addDays(new Date(), -30))
  const start = url.searchParams.get("start_date") ?? defaultStart
  const end = url.searchParams.get("end_date") ?? today
  return {
    startDate: start,
    endDate: end
  }
}

export async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input)
  const digest = await crypto.subtle.digest("SHA-256", bytes)
  return [...new Uint8Array(digest)].map((n) => n.toString(16).padStart(2, "0")).join("")
}

export function base64UrlEncode(bytes: Uint8Array): string {
  const base64 = btoa(String.fromCharCode(...bytes))
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
}

export function randomToken(bytes = 32): string {
  const data = new Uint8Array(bytes)
  crypto.getRandomValues(data)
  return base64UrlEncode(data)
}

export async function sleep(ms: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms))
}

export function appendQuery(url: string, params: Record<string, string>): string {
  const parsed = new URL(url)
  for (const [key, value] of Object.entries(params)) {
    parsed.searchParams.set(key, value)
  }
  return parsed.toString()
}
