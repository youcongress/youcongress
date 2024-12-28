const FactChecker = {
  mounted() {
    const editor = this.el;
    const placeholder = editor.dataset.placeholder;
    let debounceTimer;

    // Add placeholder initially
    editor.innerHTML = `<span class="text-gray-400">${placeholder}</span>`;

    editor.addEventListener('focus', () => {
      if (editor.innerHTML.includes(placeholder)) {
        editor.innerHTML = '';
      }
    });

    editor.addEventListener('blur', () => {
      if (!editor.textContent.trim()) {
        editor.innerHTML = `<span class="text-gray-400">${placeholder}</span>`;
      }
    });

    const debounceAnalysis = (text) => {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        if (text && text !== placeholder) {
          this.pushEventTo(this.el, "fact_check", { text });
        }
      }, 1000);
    };

    // Handle paste events to strip formatting
    editor.addEventListener('paste', (e) => {
      e.preventDefault();
      const text = e.clipboardData.getData('text/plain');
      document.execCommand('insertText', false, text);
      debounceAnalysis(text);
    });

    // Handle input events for typing
    editor.addEventListener('input', () => {
      const text = editor.textContent.trim();
      debounceAnalysis(text);
    });

    // Handle updates from server
    this.handleEvent("update_content", ({ analyzed_text }) => {
      let content = '';
      analyzed_text.forEach(sentence => {
        const bgColor = {
          "fact": "bg-green-200",
          "false": "bg-red-200",
          "opinion": "bg-blue-200",
          "unknown": "bg-yellow-200"
        }[sentence.classification];

        content += `<span class="${bgColor}">${sentence.text}&nbsp;</span>`;
      });
      editor.innerHTML = content;
    });
  },

  updated() {
    // Keep focus and cursor position if needed
    const selection = window.getSelection();
    const range = selection.getRangeAt(0);
    this.el.focus();
    selection.removeAllRanges();
    selection.addRange(range);
  }
};

export default FactChecker;
