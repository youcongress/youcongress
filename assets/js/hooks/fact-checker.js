const FactChecker = {
  mounted() {
    const editor = this.el;
    const placeholder = editor.dataset.placeholder;
    let debounceTimer;

    // Set initial height
    this.adjustHeight();

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

    // Add scroll event listener to adjust height
    editor.addEventListener('scroll', () => {
      if (editor.scrollHeight > editor.clientHeight &&
          editor.scrollTop + editor.clientHeight >= editor.scrollHeight - 30) {
        this.adjustHeight();
      }
    });

    const debounceAnalysis = (text) => {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        if (text && text !== placeholder) {
          try {
            window.dispatchEvent(new Event("phx:page-loading-start"));
            this.pushEventTo(this.el, "fact_check", { text });
          } catch (error) {
            console.error("Error during fact check:", error);
          }
        }
      }, 1500);
    };

    editor.addEventListener('paste', (e) => {
      e.preventDefault();
      const text = e.clipboardData.getData('text/plain');
      document.execCommand('insertText', false, text);
      this.adjustHeight();
      debounceAnalysis(text);
    });

    editor.addEventListener('input', () => {
      const text = editor.textContent.trim();
      debounceAnalysis(text);
    });

    this.handleEvent("update_content", ({ analyzed_text }) => {
      try {
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
      } catch (error) {
        console.error("Error updating content:", error);
      } finally {
        window.dispatchEvent(new Event("phx:page-loading-stop"));
      }
    });
  },

  adjustHeight() {
    const editor = this.el;

    // Set initial height if not already set
    if (!editor.style.height) {
      editor.style.height = '150px';
      return;
    }

    const viewportHeight = window.innerHeight;
    const editorRect = editor.getBoundingClientRect();
    const currentHeight = editorRect.height;

    // Increase height by 100px or to fill available space
    const newHeight = Math.min(
      currentHeight + 100,
      viewportHeight - editorRect.top - 40 // Leave 40px padding at bottom
    );

    editor.style.height = `${newHeight}px`;
  }
};

export default FactChecker;
