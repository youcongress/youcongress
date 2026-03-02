const SessionLogin = {
  mounted() {
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
        }
      }).catch(() => {
        // Ignore errors; user can refresh if needed
      })
    })
  },

  csrfToken() {
    const meta = document.querySelector("meta[name='csrf-token']")
    return meta ? meta.getAttribute("content") : ""
  }
}

export default SessionLogin
