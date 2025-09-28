const QuoteMenu = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const button = this.el.querySelector('button');
      const expanded = button.getAttribute('aria-expanded') === 'true';
      button.setAttribute('aria-expanded', String(!expanded));
      const menu = this.el.querySelector('.absolute');

      if (expanded) {
        menu.classList.add("hidden");
      } else {
        menu.classList.remove("hidden");
      }
    });
  }
};

export default QuoteMenu;
