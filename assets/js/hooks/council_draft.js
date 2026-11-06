export default {
  mounted() {
    if (this.el.dataset.guest !== "true") return
    try {
      const draft = JSON.parse(sessionStorage.getItem("youcongress-council-draft"))
      if (draft) this.pushEvent("restore-draft", {draft})
    } catch (_) { /* Storage is optional. */ }
    this.handleEvent("store-council-draft", ({draft}) => {
      try { sessionStorage.setItem("youcongress-council-draft", JSON.stringify(draft)) } catch (_) {}
    })
  }
}
