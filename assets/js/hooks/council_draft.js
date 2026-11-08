const key = "youcongress-council-draft"
export default {
  mounted() {
    if (this.el.dataset.guest === "true" && this.el.dataset.readonly !== "true") {
      try {
        const saved = JSON.parse(sessionStorage.getItem(key))
        if (saved) this.pushEvent("restore-draft", saved.draft ? saved : {draft: saved})
      } catch (_) { /* Storage is optional. */ }
    }
    if (this.el.dataset.guest !== "true" && this.el.dataset.readonly !== "true") {
      try { sessionStorage.removeItem(key) } catch (_) {}
    }
    this.handleEvent("store-council-draft", payload => {
      try { sessionStorage.setItem(key, JSON.stringify(payload)) } catch (_) {}
    })
    this.handleEvent("clear-council-draft", () => {
      try { sessionStorage.removeItem(key) } catch (_) {}
    })
    this.handleEvent("council-person-added", ({id}) => {
      const member = document.getElementById(`council-member-${id}`)
      if (!member || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
      member.animate([
        {opacity: 0, transform: "translateY(-8px)"},
        {opacity: 1, transform: "translateY(0)"}
      ], {duration: 240, delay: 180, fill: "backwards", easing: "ease-out"})
    })
    this.onClick = async event => {
      const button = event.target.closest("[data-council-copy], [data-council-share]")
      if (!button) return
      const status = this.el.querySelector("#council-copy-status")
      try {
        const text = button.dataset.councilCopy || button.dataset.councilShare
        if (button.dataset.councilShare && navigator.share) {
          await navigator.share({text})
        } else {
          await navigator.clipboard.writeText(text)
          if (status) status.textContent = "Copied. Ready to share."
          const previous = button.textContent
          button.textContent = "✓ Copied"
          setTimeout(() => { if (button.isConnected) button.textContent = previous }, 2500)
        }
      } catch (error) {
        if (error.name !== "AbortError" && status) status.textContent = "Could not copy automatically. Select and copy the link above."
      }
    }
    this.el.addEventListener("click", this.onClick)
  },
  destroyed() { this.el.removeEventListener("click", this.onClick) }
}
