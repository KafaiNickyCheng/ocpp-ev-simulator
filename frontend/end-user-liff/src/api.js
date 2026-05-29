// src/api.js
// All REST calls to the OCPP backend.
// Replace BACKEND_URL with your actual server URL (ngrok / production).

const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || 'http://localhost:5000'

async function request(method, path, body) {
  const res = await fetch(`${BACKEND_URL}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(text || `HTTP ${res.status}`)
  }
  const text = await res.text()
  return text ? JSON.parse(text) : null
}

// ── Charge Points ──────────────────────────────────────────────
export const getChargePoints = () => request('GET', '/api/chargepoints')
export const getChargePoint  = (id) => request('GET', `/api/chargepoints/${id}`)

// ── Sessions / Transactions ────────────────────────────────────
export const getMyTransactions = (lineUserId) =>
  request('GET', `/api/transactions/by-line/${lineUserId}`)

export const getActiveTransaction = (lineUserId) =>
  request('GET', `/api/transactions/active/by-line/${lineUserId}`)

// ── Remote Commands ────────────────────────────────────────────
export const remoteStart = (chargePointId, connectorId, idTag) =>
  request('POST', `/api/chargepoints/${chargePointId}/remote-start`, {
    connectorId,
    idTag,
  })

export const remoteStop = (chargePointId, transactionId) =>
  request('POST', `/api/chargepoints/${chargePointId}/remote-stop`, {
    transactionId,
  })

// ── IdTag Management ───────────────────────────────────────────
export const getMyTag = (lineUserId) =>
  request('GET', `/api/tags/by-line/${lineUserId}`)                // ← changed

export const createTag = (lineUserId, displayName) =>
  request('POST', '/api/tags/line', { lineUserId, displayName })

export const deactivateTag = (tagId) =>
  request('DELETE', `/api/tags/${tagId}`)
