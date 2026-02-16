function b64ToBytes(value: string): Uint8Array {
  const binary = atob(value)
  return Uint8Array.from(binary, (char) => char.charCodeAt(0))
}

function bytesToB64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
}

function asArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer
}

async function importAesKey(base64Key: string): Promise<CryptoKey> {
  const keyBytes = b64ToBytes(base64Key)
  if (keyBytes.byteLength !== 32) {
    throw new Error("TOKEN_ENCRYPTION_KEY must be base64 encoded 32-byte key")
  }
  return crypto.subtle.importKey("raw", asArrayBuffer(keyBytes), "AES-GCM", false, ["encrypt", "decrypt"])
}

export async function encryptSecret(secret: string, base64Key: string): Promise<string> {
  const key = await importAesKey(base64Key)
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const plaintext = new TextEncoder().encode(secret)
  const cipherBuffer = await crypto.subtle.encrypt({ name: "AES-GCM", iv: asArrayBuffer(iv) }, key, plaintext)
  const cipher = new Uint8Array(cipherBuffer)
  return `${bytesToB64(iv)}:${bytesToB64(cipher)}`
}

export async function decryptSecret(encrypted: string, base64Key: string): Promise<string> {
  const [ivB64, cipherB64] = encrypted.split(":")
  if (!ivB64 || !cipherB64) {
    throw new Error("Invalid encrypted secret format")
  }
  const key = await importAesKey(base64Key)
  const iv = b64ToBytes(ivB64)
  const cipher = b64ToBytes(cipherB64)
  const plainBuffer = await crypto.subtle.decrypt({ name: "AES-GCM", iv: asArrayBuffer(iv) }, key, asArrayBuffer(cipher))
  return new TextDecoder().decode(plainBuffer)
}

export async function computeWebhookSignatureHexUpper(
  clientSecret: string,
  timestamp: string,
  rawBody: string
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(clientSecret),
    {
      name: "HMAC",
      hash: "SHA-256"
    },
    false,
    ["sign"]
  )

  const payload = new TextEncoder().encode(`${timestamp}${rawBody}`)
  const signature = await crypto.subtle.sign("HMAC", key, payload)
  return [...new Uint8Array(signature)].map((n) => n.toString(16).padStart(2, "0")).join("").toUpperCase()
}
