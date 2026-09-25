// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import QuoteMenu from "./hooks/quote_menu"
import Turnstile from "./hooks/turnstile"
import SessionLogin from "./hooks/session_login"
import InfiniteScroll from "./hooks/infinite_scroll"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {
  QuoteMenu: QuoteMenu,
  Turnstile: Turnstile,
  SessionLogin: SessionLogin,
  InfiniteScroll: InfiniteScroll
};

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

async function writeToClipboard(text) {
  if ((navigator.clipboard && window.isSecureContext)) {
    return navigator.clipboard.writeText(text)
  }

  const textarea = document.createElement("textarea")
  textarea.value = text
  textarea.style.position = "fixed"
  textarea.style.top = "-1000px"
  textarea.style.left = "-1000px"
  document.body.appendChild(textarea)
  textarea.focus()
  textarea.select()

  try {
    document.execCommand("copy")
  } finally {
    document.body.removeChild(textarea)
  }
}

function setupCopyButtons() {
  document.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-copy-target], [data-copy-current-url]")
    if (!button) return

    let text = ""

    if (button.hasAttribute("data-copy-current-url")) {
      text = window.location.href
    } else {
      const targetId = button.dataset.copyTarget
      if (!targetId) return

      const content = document.getElementById(targetId)
      if (!content) return

      text = content.innerText.trim()
    }

    if (!text) return

    try {
      await writeToClipboard(text)
      const originalLabel = button.getAttribute("data-original-label") || button.getAttribute("aria-label") || button.innerText.trim() || "Copy"
      button.setAttribute("data-original-label", originalLabel)

      const originalText = button.getAttribute("data-original-text") || button.innerText.trim()
      const successLabel = button.dataset.copySuccessLabel
      // Keep the accessible name in sync with the visible text (WCAG 2.5.3).
      button.setAttribute("aria-label", successLabel || "Copied!")
      if (successLabel) {
        button.setAttribute("data-original-text", originalText)
        button.textContent = successLabel
      }

      button.classList.add("text-blue-600")
      setTimeout(() => {
        button.classList.remove("text-blue-600")
        button.setAttribute("aria-label", button.getAttribute("data-original-label") || "Copy")
        if (successLabel) {
          button.textContent = button.getAttribute("data-original-text") || originalText
        }
      }, 1500)
    } catch (error) {
      console.error("Unable to copy text", error)
    }
  })
}

setupCopyButtons()

const COOKIE_CONSENT_NAME = "youcongress_cookie_consent"
const COOKIE_CONSENT_MAX_AGE = 60 * 60 * 24 * 365

function readCookie(name) {
  const prefix = `${encodeURIComponent(name)}=`
  const cookie = document.cookie.split("; ").find((item) => item.startsWith(prefix))
  return cookie ? decodeURIComponent(cookie.slice(prefix.length)) : null
}

function writeCookieConsent(value) {
  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  document.cookie = `${encodeURIComponent(COOKIE_CONSENT_NAME)}=${encodeURIComponent(value)}; Path=/; Max-Age=${COOKIE_CONSENT_MAX_AGE}; SameSite=Lax${secure}`
}

function setupCookieBanner() {
  const banner = document.getElementById("cookie-banner")
  if (!banner) return

  const showBanner = () => {
    banner.style.removeProperty("display")
    banner.querySelector("[data-cookie-consent='accepted']")?.focus()
  }

  if (!readCookie(COOKIE_CONSENT_NAME)) showBanner()

  document.addEventListener("click", (event) => {
    const settingsButton = event.target.closest("[data-cookie-settings]")
    if (settingsButton) {
      showBanner()
      return
    }

    const consentButton = event.target.closest("[data-cookie-consent]")
    if (!consentButton) return

    banner.style.display = "none"
    writeCookieConsent(consentButton.dataset.cookieConsent)
    window.location.reload()
  })
}

setupCookieBanner()

window.addEventListener("phx:clear-autocomplete", (event) => {
  const inputId = event.detail && event.detail.id
  const input = inputId && document.getElementById(inputId)

  if (input) input.value = ""
})
