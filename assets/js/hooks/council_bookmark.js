export default {
  mounted() {
    this.onOtherOpen = (event) => {
      if (event.detail !== this.el.id && this.el.dataset.open === "true") {
        this.pushEventTo(this.el, "close", {})
      }
    }
    this.onInteraction = (event) => {
      if (event.target.closest('[role="dialog"]') && !event.target.hasAttribute("data-council-heading")) {
        clearTimeout(this.timer)
      }
      if (event.type !== "focusin" && event.target.closest('[role="dialog"]')) clearTimeout(this.timer)
    }
    window.addEventListener("council-bookmark-open", this.onOtherOpen)
    for (const type of ["pointerdown", "click", "keydown", "focusin"]) this.el.addEventListener(type, this.onInteraction)
    this.syncPopup()
  },
  updated() { this.syncPopup() },
  destroyed() {
    clearTimeout(this.timer)
    window.removeEventListener("council-bookmark-open", this.onOtherOpen)
    for (const type of ["pointerdown", "click", "keydown", "focusin"]) this.el.removeEventListener(type, this.onInteraction)
  },
  syncPopup() {
    const open = this.el.dataset.open === "true"
    if (this.el.dataset.error === "true") clearTimeout(this.timer)
    const key = `${open}:${this.el.dataset.opening}`
    if (key === this.popupKey) return
    this.popupKey = key
    clearTimeout(this.timer)
    const wasOpen = this.wasOpen
    this.wasOpen = open
    if (!open) {
      if (wasOpen && (document.activeElement === document.body || this.el.contains(document.activeElement))) {
        this.el.querySelector("button")?.focus({preventScroll: true})
      }
      return
    }
    window.dispatchEvent(new CustomEvent("council-bookmark-open", {detail: this.el.id}))
    this.el.querySelector("[data-council-heading]")?.focus({preventScroll: true})
    if (this.el.dataset.error !== "true") {
      const opening = Number(this.el.dataset.opening)
      this.timer = setTimeout(() => this.pushEventTo(this.el, "dismiss", {opening}), 6500)
    }
  }
}
