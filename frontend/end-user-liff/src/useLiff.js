// src/useLiff.js
import { useState, useEffect } from 'react'
import liff from '@line/liff'

const LIFF_ID = import.meta.env.VITE_LIFF_ID || 'YOUR_LIFF_ID_HERE'

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
        let profile = null

        if (loggedIn) {
          try {
            profile = await liff.getProfile()
          } catch (e) {
            console.warn('Could not fetch profile:', e)
          }
        }

        setState({
          ready: true,
          loggedIn,
          profile,
          error: null,
          isInClient: liff.isInClient(),
        })
      })
      .catch((err) => {
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
