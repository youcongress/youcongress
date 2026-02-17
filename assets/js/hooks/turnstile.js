const Turnstile = {
  mounted() {
    const siteKey = this.el.dataset.sitekey;
    if (!siteKey) return;

    this.handleEvent("reset_turnstile", () => {
      if (this.widgetId) {
        window.turnstile.reset(this.widgetId);
      }
    });

    if (!window.turnstile) {
      const script = document.createElement("script");
      script.src =
        "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
      script.async = true;
      script.onload = () => this.renderWidget(siteKey);
      document.head.appendChild(script);
    } else {
      this.renderWidget(siteKey);
    }
  },

  renderWidget(siteKey) {
    this.widgetId = window.turnstile.render(this.el, {
      sitekey: siteKey,
      callback: (token) => {
        // Set the token in a hidden input so it's submitted with the form
        const form = this.el.closest("form");
        let input = form.querySelector('input[name="cf-turnstile-response"]');
        if (!input) {
          input = document.createElement("input");
          input.type = "hidden";
          input.name = "cf-turnstile-response";
          form.appendChild(input);
        }
        input.value = token;
      },
    });
  },
};

export default Turnstile;
