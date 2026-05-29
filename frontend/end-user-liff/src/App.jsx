// src/App.jsx
import { useState, useEffect, useCallback } from 'react'
import { useLiff } from './useLiff'
import * as api from './api'
import './App.css'

// ── Tiny icon set (inline SVG) ─────────────────────────────────
const Icon = {
  Bolt:    () => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>,
  Stop:    () => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="3" y="3" width="18" height="18" rx="2"/></svg>,
  Tag:     () => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M20.59 13.41l-7.17 7.17a2 2 0 01-2.83 0L2 12V2h10l8.59 8.59a2 2 0 010 2.82z"/><line x1="7" y1="7" x2="7.01" y2="7"/></svg>,
  Station: () => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="2" y="2" width="20" height="20" rx="2"/><path d="M7 18V8l5-4 5 4v10"/><path d="M10 18v-4h4v4"/></svg>,
  History: () => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>,
  User:    () => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>,
  Check:   () => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><polyline points="20 6 9 17 4 12"/></svg>,
  X:       () => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>,
  Refresh: () => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 11-2.12-9.36L23 10"/></svg>,
  Plug:    () => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 22v-5"/><path d="M9 8V2"/><path d="M15 8V2"/><path d="M18 8v5a4 4 0 01-4 4h-4a4 4 0 01-4-4V8z"/></svg>,
  Trash:   () => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4h6v2"/></svg>,
}

// ── Status badge ───────────────────────────────────────────────
function StatusDot({ status }) {
  const map = {
    Available:   { color: 'var(--accent)', label: 'Available' },
    Charging:    { color: 'var(--blue)',   label: 'Charging' },
    Preparing:   { color: 'var(--amber)',  label: 'Preparing' },
    Finishing:   { color: 'var(--amber)',  label: 'Finishing' },
    Unavailable: { color: 'var(--text-dim)', label: 'Unavailable' },
    Faulted:     { color: 'var(--red)',    label: 'Faulted' },
  }
  const s = map[status] || { color: 'var(--text-dim)', label: status }
  return (
    <span className="status-badge" style={{ '--dot-color': s.color }}>
      <span className="dot" />
      {s.label}
    </span>
  )
}

// ── Toast ──────────────────────────────────────────────────────
function Toast({ toasts }) {
  return (
    <div className="toast-stack">
      {toasts.map(t => (
        <div key={t.id} className={`toast toast--${t.type}`}>
          <span className="toast-icon">
            {t.type === 'success' ? <Icon.Check /> : <Icon.X />}
          </span>
          {t.msg}
        </div>
      ))}
    </div>
  )
}

// ── Loading screen ─────────────────────────────────────────────
function LoadingScreen() {
  return (
    <div className="loading-screen">
      <div className="loading-logo">
        <span className="loading-bolt"><Icon.Bolt /></span>
      </div>
      <p className="loading-text mono">Initializing LIFF…</p>
    </div>
  )
}

// ── Login screen ───────────────────────────────────────────────
function LoginScreen({ onLogin }) {
  return (
    <div className="login-screen">
      <div className="login-hero">
        <div className="login-icon"><Icon.Plug /></div>
        <h1 className="login-title mono">EV<br/>Charge</h1>
        <p className="login-sub">OCPP 1.6 Smart Charging</p>
      </div>
      <button className="btn btn--line" onClick={onLogin}>
        Continue with LINE
      </button>
    </div>
  )
}

// ── Nav bar ────────────────────────────────────────────────────
function NavBar({ tab, onTab }) {
  const tabs = [
    { id: 'charge',  label: 'Charge',  icon: Icon.Bolt },
    { id: 'session', label: 'Session', icon: Icon.Plug },
    { id: 'history', label: 'History', icon: Icon.History },
    { id: 'profile', label: 'Profile', icon: Icon.User },
  ]
  return (
    <nav className="navbar">
      {tabs.map(t => (
        <button
          key={t.id}
          className={`nav-btn ${tab === t.id ? 'active' : ''}`}
          onClick={() => onTab(t.id)}
        >
          <span className="nav-icon"><t.icon /></span>
          <span className="nav-label">{t.label}</span>
        </button>
      ))}
    </nav>
  )
}

// ── Charge tab ─────────────────────────────────────────────────
function ChargeTab({ myTag, onToast, onSessionChange }) {
  const [stations, setStations]     = useState([])
  const [loading, setLoading]       = useState(true)
  const [starting, setStarting]     = useState(null) // connectorId being started

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const data = await api.getChargePoints()
      setStations(data || [])
    } catch {
      onToast('error', 'Could not load stations')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { load() }, [load])

  async function handleStart(cpId, connectorId) {
    if (!myTag) return onToast('error', 'No IdTag — create one in Profile first')
    setStarting(`${cpId}-${connectorId}`)
    try {
      await api.remoteStart(cpId, connectorId, myTag.tagId)
      onToast('success', `Charging started on ${cpId} connector ${connectorId}`)
      onSessionChange()
    } catch (e) {
      onToast('error', e.message || 'Start failed')
    } finally {
      setStarting(null)
    }
  }

  if (loading) return <div className="tab-loading"><div className="spinner" /></div>

  return (
    <div className="tab-content fade-up">
      <div className="tab-header">
        <h2 className="tab-title mono">Stations</h2>
        <button className="icon-btn" onClick={load}><Icon.Refresh /></button>
      </div>

      {stations.length === 0 ? (
        <div className="empty-state">
          <Icon.Station />
          <p>No stations found</p>
        </div>
      ) : stations.map(cp => (
        <div key={cp.chargePointId} className="card station-card">
          <div className="station-header">
            <div>
              <div className="station-id mono">{cp.chargePointId}</div>
              <div className="station-model">{cp.vendor} {cp.model}</div>
            </div>
            <span className={`online-badge ${cp.isOnline ? 'online' : 'offline'}`}>
              {cp.isOnline ? 'Online' : 'Offline'}
            </span>
          </div>

          <div className="connector-list">
            {(cp.connectors || []).map(c => (
              <div key={c.connectorId} className="connector-row">
                <div className="connector-info">
                  <span className="connector-num mono">#{c.connectorId}</span>
                  <StatusDot status={c.status} />
                </div>
                {c.status === 'Available' && cp.isOnline && (
                  <button
                    className="btn btn--sm btn--accent"
                    disabled={starting === `${cp.chargePointId}-${c.connectorId}`}
                    onClick={() => handleStart(cp.chargePointId, c.connectorId)}
                  >
                    {starting === `${cp.chargePointId}-${c.connectorId}`
                      ? <span className="spinner-sm" />
                      : <><Icon.Bolt /> Start</>
                    }
                  </button>
                )}
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}

// ── Session tab ────────────────────────────────────────────────
function SessionTab({ lineUserId, onToast, refreshKey }) {
  const [session, setSession] = useState(null)
  const [loading, setLoading] = useState(true)
  const [stopping, setStopping] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const data = await api.getActiveTransaction(lineUserId)
      setSession(data)
    } catch {
      setSession(null)
    } finally {
      setLoading(false)
    }
  }, [lineUserId])

  useEffect(() => { load() }, [load, refreshKey])

  // Auto-refresh every 15s when session is active
  useEffect(() => {
    if (!session) return
    const t = setInterval(load, 15000)
    return () => clearInterval(t)
  }, [session, load])

  async function handleStop() {
    if (!session) return
    setStopping(true)
    try {
      await api.remoteStop(session.chargePointId, session.transactionId)
      onToast('success', 'Session stopped')
      setSession(null)
    } catch (e) {
      onToast('error', e.message || 'Stop failed')
    } finally {
      setStopping(false)
    }
  }

  if (loading) return <div className="tab-loading"><div className="spinner" /></div>

  if (!session) return (
    <div className="tab-content fade-up">
      <div className="tab-header"><h2 className="tab-title mono">Active Session</h2></div>
      <div className="empty-state">
        <Icon.Plug />
        <p>No active session</p>
        <p className="empty-hint">Go to Stations to start charging</p>
      </div>
    </div>
  )

  const energyKwh = session.meterStop != null
    ? ((session.meterStop - session.meterStart) / 1000).toFixed(2)
    : session.currentEnergyWh != null
    ? (session.currentEnergyWh / 1000).toFixed(2)
    : '—'

  const duration = session.startTime
    ? formatDuration(new Date() - new Date(session.startTime))
    : '—'

  return (
    <div className="tab-content fade-up">
      <div className="tab-header">
        <h2 className="tab-title mono">Active Session</h2>
        <button className="icon-btn" onClick={load}><Icon.Refresh /></button>
      </div>

      <div className="card session-card">
        <div className="session-glow" />
        <div className="session-stat-grid">
          <div className="session-stat">
            <div className="stat-value mono">{energyKwh}</div>
            <div className="stat-label">kWh delivered</div>
          </div>
          <div className="session-stat">
            <div className="stat-value mono">{duration}</div>
            <div className="stat-label">duration</div>
          </div>
          <div className="session-stat">
            <div className="stat-value mono">{session.chargePointId || '—'}</div>
            <div className="stat-label">station</div>
          </div>
          <div className="session-stat">
            <div className="stat-value mono">#{session.connectorNumber || session.connectorId || '—'}</div>
            <div className="stat-label">connector</div>
          </div>
        </div>

        <div className="session-meta">
          <span className="meta-row">
            <span className="meta-key">Tx ID</span>
            <span className="meta-val mono">{session.transactionId}</span>
          </span>
          <span className="meta-row">
            <span className="meta-key">Tag</span>
            <span className="meta-val mono">{session.idTag}</span>
          </span>
          <span className="meta-row">
            <span className="meta-key">Started</span>
            <span className="meta-val">{formatTime(session.startTime)}</span>
          </span>
        </div>

        <button
          className="btn btn--danger btn--full"
          onClick={handleStop}
          disabled={stopping}
        >
          {stopping ? <span className="spinner-sm" /> : <><Icon.Stop /> Stop Charging</>}
        </button>
      </div>
    </div>
  )
}

// ── History tab ────────────────────────────────────────────────
function HistoryTab({ lineUserId }) {
  const [txs, setTxs]       = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    api.getMyTransactions(lineUserId)
      .then(data => setTxs(data || []))
      .catch(() => setTxs([]))
      .finally(() => setLoading(false))
  }, [lineUserId])

  if (loading) return <div className="tab-loading"><div className="spinner" /></div>

  return (
    <div className="tab-content fade-up">
      <div className="tab-header"><h2 className="tab-title mono">History</h2></div>

      {txs.length === 0 ? (
        <div className="empty-state">
          <Icon.History />
          <p>No transactions yet</p>
        </div>
      ) : txs.map(tx => (
        <div key={tx.id} className="card history-card">
          <div className="history-row">
            <div>
              <div className="history-station mono">{tx.chargePointId}</div>
              <div className="history-time">{formatTime(tx.startTime)}</div>
            </div>
            <div className="history-right">
              <div className="history-energy mono">
                {tx.energyDeliveredKwh != null
                  ? `${tx.energyDeliveredKwh.toFixed(2)} kWh`
                  : '—'}
              </div>
              <span className={`tx-status-badge ${(tx.status ?? 'unknown').toLowerCase()}`}>
                {tx.status ?? 'Unknown'}
              </span>
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}

// ── Profile tab ────────────────────────────────────────────────
function ProfileTab({ profile, lineUserId, onToast, onLogout }) {
  const [tag, setTag]           = useState(null)
  const [loading, setLoading]   = useState(true)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState(false)

  const loadTag = useCallback(async () => {
    setLoading(true)
    try {
      const data = await api.getMyTag(lineUserId)
      setTag(data)
    } catch {
      setTag(null)
    } finally {
      setLoading(false)
    }
  }, [lineUserId])

  useEffect(() => { loadTag() }, [loadTag])

  async function handleCreate() {
    setCreating(true)
    try {
      const t = await api.createTag(lineUserId, profile?.displayName || 'LINE User')
      setTag(t)
      onToast('success', `Tag created: ${t.tagId}`)
    } catch (e) {
      onToast('error', e.message || 'Could not create tag')
    } finally {
      setCreating(false)
    }
  }

  async function handleDelete() {
    if (!tag || !confirm('Deactivate your IdTag?')) return
    setDeleting(true)
    try {
      await api.deactivateTag(tag.id)
      setTag(null)
      onToast('success', 'Tag deactivated')
    } catch (e) {
      onToast('error', e.message || 'Could not deactivate tag')
    } finally {
      setDeleting(false)
    }
  }

  return (
    <div className="tab-content fade-up">
      <div className="tab-header"><h2 className="tab-title mono">Profile</h2></div>

      {/* LINE Profile */}
      <div className="card profile-card">
        {profile?.pictureUrl && (
          <img className="avatar" src={profile.pictureUrl} alt="avatar" />
        )}
        <div className="profile-info">
          <div className="profile-name">{profile?.displayName || 'LINE User'}</div>
          <div className="profile-id mono">{lineUserId?.slice(0, 16)}…</div>
        </div>
      </div>

      {/* IdTag */}
      <div className="section-label mono">RFID / IdTag</div>
      {loading ? (
        <div className="tab-loading"><div className="spinner" /></div>
      ) : tag ? (
        <div className="card tag-card">
          <div className="tag-info">
            <div className="tag-id mono">{tag.tagId}</div>
            <span className={`tag-status ${tag.status.toLowerCase()}`}>{tag.status}</span>
          </div>
          {tag.expiryDate && (
            <div className="tag-expiry">Expires {formatTime(tag.expiryDate)}</div>
          )}
          <button
            className="btn btn--ghost btn--sm"
            onClick={handleDelete}
            disabled={deleting}
          >
            {deleting ? <span className="spinner-sm" /> : <><Icon.Trash /> Deactivate Tag</>}
          </button>
        </div>
      ) : (
        <div className="card tag-empty-card">
          <p className="tag-empty-text">No IdTag registered. Create one to start charging.</p>
          <button
            className="btn btn--accent btn--full"
            onClick={handleCreate}
            disabled={creating}
          >
            {creating ? <span className="spinner-sm" /> : <><Icon.Tag /> Create IdTag</>}
          </button>
        </div>
      )}

      {/* Logout */}
      <button className="btn btn--ghost btn--full logout-btn" onClick={onLogout}>
        Sign out
      </button>
    </div>
  )
}

// ── Helpers ────────────────────────────────────────────────────
function formatTime(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('en-US', {
    month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit',
  })
}

function formatDuration(ms) {
  const total = Math.floor(ms / 1000)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m ${s}s`
  return `${s}s`
}

// ── Root App ───────────────────────────────────────────────────
export default function App() {
  const { ready, loggedIn, profile, error, login, logout } = useLiff()
  const [tab, setTab]         = useState('charge')
  const [toasts, setToasts]   = useState([])
  const [myTag, setMyTag]     = useState(null)
  const [sessionRefresh, setSessionRefresh] = useState(0)

  const lineUserId = profile?.userId

  // Load tag once logged in
  useEffect(() => {
    if (!lineUserId) return
    api.getMyTag(lineUserId).then(setMyTag).catch(() => setMyTag(null))
  }, [lineUserId])

  function toast(type, msg) {
    const id = Date.now()
    setToasts(t => [...t, { id, type, msg }])
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), 3500)
  }

  if (!ready) return <LoadingScreen />
  if (error)  return (
    <div className="login-screen">
      <div className="error-box">
        <p className="mono" style={{ color: 'var(--red)' }}>LIFF init failed</p>
        <p style={{ color: 'var(--text-muted)', fontSize: 13 }}>{error}</p>
      </div>
    </div>
  )
  if (!loggedIn) return <LoginScreen onLogin={login} />

  return (
    <div className="app">
      <Toast toasts={toasts} />

      <main className="main">
        {tab === 'charge' && (
          <ChargeTab
            myTag={myTag}
            onToast={toast}
            onSessionChange={() => { setSessionRefresh(r => r + 1); setTab('session') }}
          />
        )}
        {tab === 'session' && (
          <SessionTab
            lineUserId={lineUserId}
            onToast={toast}
            refreshKey={sessionRefresh}
          />
        )}
        {tab === 'history' && (
          <HistoryTab lineUserId={lineUserId} />
        )}
        {tab === 'profile' && (
          <ProfileTab
            profile={profile}
            lineUserId={lineUserId}
            onToast={toast}
            onLogout={logout}
          />
        )}
      </main>

      <NavBar tab={tab} onTab={setTab} />
    </div>
  )
}
