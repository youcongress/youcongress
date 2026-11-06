export default {
  mounted() {
    this.onOtherOpen = (event) => {
      if (event.detail !== this.el.id && this.el.dataset.open === "true") {
        this.pushEventTo(this.el, "close", {})
      }
    }
    window.addEventListener("council-bookmark-open", this.onOtherOpen)
    this.syncPopup()
  },
  updated() { this.syncPopup() },
  destroyed() {
    clearTimeout(this.timer)
    window.removeEventListener("council-bookmark-open", this.onOtherOpen)
  },
  syncPopup() {
    const open = this.el.dataset.open === "true"
    const expanded = this.el.dataset.expanded === "true"
    const key = `${open}:${expanded}:${this.el.dataset.notice}`
    if (key === this.popupKey) return
    const wasOpen = this.wasOpen
    this.popupKey = key
    this.wasOpen = open
    clearTimeout(this.timer)
    if (!open) {
      if (wasOpen && (document.activeElement === document.body || this.el.contains(document.activeElement))) {
        this.el.querySelector("button")?.focus({preventScroll: true})
      }
      return
    }
    if (!wasOpen) window.dispatchEvent(new CustomEvent("council-bookmark-open", {detail: this.el.id}))
    if (expanded) {
      this.el.querySelector("[data-council-heading]")?.focus({preventScroll: true})
    } else if (Number(this.el.dataset.notice) > 0) {
      const notice = this.el.dataset.notice
      this.timer = setTimeout(() => this.pushEventTo(this.el, "dismiss", {notice}), 6500)
    }
  }
}
