const ReconsiderMotionAd = {
  mounted() {
    this.durations = [3400, 3800, 3600, 3900, 5200, 5200]
    this.totalDuration = this.durations.reduce((total, duration) => total + duration, 0)
    this.scenes = Array.from(this.el.querySelectorAll("[data-ad-scene]"))
    this.segments = Array.from(this.el.querySelectorAll("[data-ad-segment]"))
    this.percentage = this.el.querySelector("[data-ad-percentage]")
    this.exampleLabel = this.el.querySelector("[data-ad-example]")
    this.toggleButton = this.el.querySelector("[data-ad-toggle]")
    this.replayButton = this.el.querySelector("[data-ad-replay]")
    this.playIcon = this.el.querySelector("[data-ad-play-icon]")
    this.pauseIcon = this.el.querySelector("[data-ad-pause-icon]")
    this.elapsed = 0
    this.lastFrame = performance.now()
    this.activeScene = -1
    this.playing = !window.matchMedia("(prefers-reduced-motion: reduce)").matches

    if (!this.playing) {
      this.elapsed = this.durations.slice(0, 5).reduce((total, duration) => total + duration, 0)
    }

    this.onToggle = () => {
      this.playing = !this.playing
      this.lastFrame = performance.now()
      this.updateControls()
    }

    this.onReplay = () => {
      this.elapsed = 0
      this.playing = true
      this.lastFrame = performance.now()
      this.scenes.forEach((scene) => scene.classList.remove("is-active"))
      void this.el.offsetWidth
      this.activeScene = -1
      this.render()
      this.updateControls()
    }

    this.toggleButton?.addEventListener("click", this.onToggle)
    this.replayButton?.addEventListener("click", this.onReplay)
    this.render()
    this.updateControls()
    this.animationFrame = requestAnimationFrame((now) => this.tick(now))
  },

  destroyed() {
    cancelAnimationFrame(this.animationFrame)
    this.toggleButton?.removeEventListener("click", this.onToggle)
    this.replayButton?.removeEventListener("click", this.onReplay)
  },

  tick(now) {
    const delta = Math.min(200, now - this.lastFrame)
    this.lastFrame = now

    if (this.playing) {
      this.elapsed = (this.elapsed + delta) % this.totalDuration
      this.render()
    }

    this.animationFrame = requestAnimationFrame((nextNow) => this.tick(nextNow))
  },

  render() {
    let accumulated = 0
    let sceneIndex = this.durations.length - 1
    let localElapsed = 0

    for (let index = 0; index < this.durations.length; index += 1) {
      if (this.elapsed < accumulated + this.durations[index]) {
        sceneIndex = index
        localElapsed = this.elapsed - accumulated
        break
      }

      accumulated += this.durations[index]
    }

    if (sceneIndex !== this.activeScene) {
      this.scenes.forEach((scene, index) => {
        const active = index === sceneIndex
        scene.hidden = !active
        scene.classList.toggle("is-active", active)
      })
      this.exampleLabel?.toggleAttribute("hidden", sceneIndex === 0 || sceneIndex === 5)
      this.activeScene = sceneIndex
    }

    this.segments.forEach((segment, index) => {
      const progress = index < sceneIndex
        ? 100
        : index > sceneIndex
          ? 0
          : Math.min(100, (localElapsed / this.durations[index]) * 100)

      segment.style.width = `${progress}%`
    })

    if (this.percentage) {
      const progress = Math.min(1, Math.max(0, (localElapsed - 200) / 1600))
      this.percentage.textContent = sceneIndex === 4
        ? Math.round(75 * (1 - Math.pow(1 - progress, 3)))
        : 75
    }
  },

  updateControls() {
    if (!this.toggleButton) return

    this.toggleButton.setAttribute("aria-label", this.playing ? "Pause animation" : "Play animation")
    this.playIcon?.toggleAttribute("hidden", this.playing)
    this.pauseIcon?.toggleAttribute("hidden", !this.playing)
    this.el.classList.toggle("is-paused", !this.playing)
  }
}

export default ReconsiderMotionAd
