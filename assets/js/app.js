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
import FactChecker from "./hooks/fact-checker"
import Turnstile from "./hooks/turnstile"
import SessionLogin from "./hooks/session_login"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {
  QuoteMenu: QuoteMenu,
  FactChecker: FactChecker,
  Turnstile: Turnstile,
  SessionLogin: SessionLogin
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

function setupPromptCopyButtons() {
  document.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-copy-target]")
    if (!button) return

    const targetId = button.dataset.copyTarget
    if (!targetId) return

    const content = document.getElementById(targetId)
    if (!content) return

    const text = content.innerText.trim()
    if (!text) return

    try {
      await writeToClipboard(text)
      const originalLabel = button.getAttribute("data-original-label") || button.getAttribute("aria-label") || "Copy prompt"
      button.setAttribute("data-original-label", originalLabel)
      button.setAttribute("aria-label", "Copied!")
      button.classList.add("text-blue-600")
      setTimeout(() => {
        button.classList.remove("text-blue-600")
        button.setAttribute("aria-label", button.getAttribute("data-original-label") || "Copy prompt")
      }, 1500)
    } catch (error) {
      console.error("Unable to copy prompt", error)
    }
  })
}

setupPromptCopyButtons()
