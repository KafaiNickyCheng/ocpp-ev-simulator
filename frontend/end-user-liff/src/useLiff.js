// src/useLiff.js
import { useState, useEffect } from 'react'
import liff from '@line/liff'

const LIFF_ID = import.meta.env.VITE_LIFF_ID || 'YOUR_LIFF_ID_HERE'

function isTokenValid() {
  try {
    const token = liff.getAccessToken()
    if (!token) return false

    // JWT payload is the second segment
    const payload = JSON.parse(atob(token.split('.')[1]))
    // Give 60s buffer before actual expiry
    return payload.exp * 1000 > Date.now() + 60_000
  } catch {
    return false
  }
}

export function useLiff() {
  const [state, setState] = useState({
    ready: false,
    loggedIn: false,
    profile: null,
    error: null,
    isInClient: false,
  })

  useEffect(() => {
    liff
      .init({
        liffId: LIFF_ID,
        withLoginOnExternalBrowser: true,
      })
      .then(async () => {
        const loggedIn = liff.isLoggedIn()

        // ── Not logged in → redirect to LINE login immediately
        if (!loggedIn) {
          liff.login()
          return
        }

        // ── Logged in but token is stale → force re-login
        if (!isTokenValid()) {
          console.warn('LIFF token invalid or expired — forcing re-login')
          liff.logout()
          liff.login()
          return
        }

        // ── Token is valid → fetch profile
        let profile = null
        try {
          profile = await liff.getProfile()
        } catch (e) {
          console.warn('Could not fetch profile:', e)
          // Profile fetch failed even with valid token
          // Force re-login rather than proceeding with null profile
          liff.logout()
          liff.login()
          return
        }

        // ── Sanity check: we must have a userId
        if (!profile?.userId) {
          console.warn('Profile missing userId — forcing re-login')
          liff.logout()
          liff.login()
          return
        }

        setState({
          ready: true,
          loggedIn: true,
          profile,
          error: null,
          isInClient: liff.isInClient(),
        })
      })
      .catch((err) => {
        console.error('LIFF init failed:', err)
        setState((s) => ({ ...s, ready: true, error: err.message }))
      })
  }, [])

  const login = () => liff.login()

  const logout = () => {
    liff.logout()
    window.location.reload()
  }

  const close = () => liff.isInClient() && liff.closeWindow()

  const sendMessage = (text) =>
    liff.sendMessages([{ type: 'text', text }]).catch(console.error)

  return { ...state, login, logout, close, sendMessage }
}