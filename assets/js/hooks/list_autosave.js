// Flush debounced form edits before navigation can destroy the editing LiveView.
export default {
  mounted() {
    this.onNavigate = event => {
      if (this.allowNavigation) { this.allowNavigation = false; return }
      if (this.el.dataset.autosave !== "true" || event.defaultPrevented ||
          event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
      const link = event.target.closest("a[href]")
      if (!link || link.target === "_blank" || link.hasAttribute("download") ||
          !/^https?:/.test(link.href) || link.getAttribute("href").startsWith("#")) return
      event.preventDefault()
      event.stopImmediatePropagation()
      const status = this.el.querySelector("#list-navigation-status")
      if (this.disconnectedFromServer) {
        status.textContent = "Waiting for a connection. Your latest edits have not been saved."
        return
      }
      if (this.navigating) return
      this.navigating = true
      status.textContent = "Saving before leaving…"
      const params = {reasons: {}}
      for (const [key, value] of new FormData(this.el)) {
        const reason = key.match(/^reasons\[(\d+)\]$/)
        if (reason) params.reasons[reason[1]] = value
        else if (["name", "slug", "link_council"].includes(key)) params[key] = value
      }
      this.pushEvent("flush-autosave", params, ({saved}) => {
        this.navigating = false
        if (saved) {
          this.allowNavigation = true
          link.click()
        }
        else status.textContent = "Your edits are still here. Resolve the save error before leaving."
      })
    }
    document.addEventListener("click", this.onNavigate, true)
  },
  disconnected() { this.disconnectedFromServer = true; this.navigating = false },
  reconnected() { this.disconnectedFromServer = false },
  destroyed() { document.removeEventListener("click", this.onNavigate, true) }
}
