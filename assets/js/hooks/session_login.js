const SessionLogin = {
  mounted() {
    this.toggleAuthPrompts()

    this.handleEvent("session-login", ({ token, redirect_to }) => {
      if (!token) return

      fetch("/users/live_login", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": this.csrfToken()
        },
        body: JSON.stringify({ token })
      }).then(() => {
        if (redirect_to) {
          window.location.href = redirect_to
        } else if (this.shouldReloadOnLogin()) {
          window.location.reload()
        }
      }).catch(() => {
        // Ignore errors; user can refresh if needed
      })
    })
  },

  updated() {
    this.toggleAuthPrompts()
  },

  toggleAuthPrompts() {
    const targets = this.hideTargets()
    if (!targets.length) return

    const step = this.el.dataset.step
    const shouldShow = !step || step === "enter_email_password"
    targets.forEach(id => {
      const container = document.getElementById(id)
      if (container) {
        container.style.display = shouldShow ? "" : "none"
      }
    })
  },

  hideTargets() {
    const list = this.el.dataset.hideTargets
    if (!list) return []

    return list
      .split(",")
      .map(id => id.trim())
      .filter(Boolean)
  },

  shouldReloadOnLogin() {
    return this.el.dataset.reloadOnLogin === "true"
  },

  csrfToken() {
    const meta = document.querySelector("meta[name='csrf-token']")
    return meta ? meta.getAttribute("content") : ""
  }
}

export default SessionLogin
