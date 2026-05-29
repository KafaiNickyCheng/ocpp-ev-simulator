// src/useLiff.js
import { useState, useEffect } from 'react'
import liff from '@line/liff'

const LIFF_ID = import.meta.env.VITE_LIFF_ID || 'YOUR_LIFF_ID_HERE'

// Prevent re-login from firing more than once per page load
let loginRedirecting = false

function isTokenValid() {
  try {
    const token = liff.getAccessToken()
    if (!token) return false
    const payload = JSON.parse(atob(token.split('.')[1]))
    return payload.exp * 1000 > Date.now() + 60_000
  } catch {
    return false
  }
}

function forceRelogin() {
  if (loginRedirecting) return  // ← guard: only redirect once
  loginRedirecting = true
  liff.logout()
  liff.login()
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

        if (!loggedIn) {
          // Not logged in at all — just show login screen, don't auto-redirect
          setState({ ready: true, loggedIn: false, profile: null, error: null, isInClient: liff.isInClient() })
          return
        }

        // Logged in but token is stale → force fresh login (only once)
        if (!isTokenValid()) {
          console.warn('LIFF token stale — re-login')
          forceRelogin()
          return
        }

        // Fetch profile
        let profile = null
        try {
          profile = await liff.getProfile()
        } catch (e) {
          console.warn('Profile fetch failed:', e)
          forceRelogin()
          return
        }

        // Must have userId
        if (!profile?.userId) {
          console.warn('No userId in profile — re-login')
          forceRelogin()
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
        console.error('LIFF init error:', err)
        setState((s) => ({ ...s, ready: true, error: err.message }))
      })
  }, [])

  const login  = () => liff.login()
  const logout = () => { liff.logout(); window.location.reload() }
  const close  = () => liff.isInClient() && liff.closeWindow()
  const sendMessage = (text) =>
    liff.sendMessages([{ type: 'text', text }]).catch(console.error)

  return { ...state, login, logout, close, sendMessage }
}