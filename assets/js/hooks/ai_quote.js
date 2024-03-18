const AIQuote = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const button = this.el.querySelector('button');
      const expanded = button.getAttribute('aria-expanded') === 'true';
      button.setAttribute('aria-expanded', String(!expanded));
      const menu = this.el.querySelector('.absolute');

      if (expanded) {
        menu.classList.add("opacity-0", "translate-y-1");
        menu.classList.remove("opacity-100", "translate-y-0");
      } else {
        menu.classList.add("opacity-100", "translate-y-0");
        menu.classList.remove("opacity-0", "translate-y-1");
      }
    });
  }
};

export default AIQuote;
