const InfiniteSearchResults = {
  mounted() {
    this.loading = false
    this.isVisible = false
    this.resultCount = this.el.dataset.resultCount

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          this.isVisible = entry.isIntersecting

          if (entry.isIntersecting) {
            this.maybeLoad()
          }
        })
      },
      { rootMargin: "200px 0px" }
    )

    this.observer.observe(this.el)
  },

  updated() {
    const nextResultCount = this.el.dataset.resultCount
    const hasMore = this.el.dataset.hasMore === "true"

    if (nextResultCount !== this.resultCount || !hasMore) {
      this.resultCount = nextResultCount
      this.loading = false
    }

    if (this.isVisible) {
      this.maybeLoad()
    }
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect()
    }
  },

  maybeLoad() {
    if (this.loading) return
    if (this.el.dataset.hasMore !== "true") return

    this.loading = true
    this.pushEvent("load-more-search", {})
  }
}

export default InfiniteSearchResults
