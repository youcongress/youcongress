// Sentinel-based infinite scroll. Put it on an element rendered below the list
// and give it:
//   data-event      - the LiveView event to push when the sentinel shows up
//   data-has-more   - "true" while there are more items to fetch
//   data-item-count - how many items are currently rendered
//
// The item count is what tells us a load actually landed, so we never push a
// second request while one is still in flight.
const InfiniteScroll = {
  mounted() {
    this.loading = false
    this.isVisible = false
    this.itemCount = this.el.dataset.itemCount

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
    const nextItemCount = this.el.dataset.itemCount
    const hasMore = this.el.dataset.hasMore === "true"

    if (nextItemCount !== this.itemCount || !hasMore) {
      this.itemCount = nextItemCount
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
    this.pushEvent(this.el.dataset.event, {})
  }
}

export default InfiniteScroll
