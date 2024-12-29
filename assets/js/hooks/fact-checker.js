const FactChecker = {
  mounted() {
    const editor = this.el;
    const placeholder = editor.dataset.placeholder;
    let debounceTimer;

    // Set initial height
    this.adjustHeight();

    // Add placeholder initially
    editor.innerHTML = `<span class="text-gray-400">${placeholder}</span>`;

    // Add paste example event listener
    window.addEventListener("paste-example", () => {
      const exampleText = `The Earth completes one rotation around its axis in approximately 24 hours, which gives us our day and night cycle. Many people believe that drinking hot water with lemon in the morning boosts metabolism and aids weight loss. Unicorns were commonly kept as pets by medieval European nobility until the 16th century. Studies have shown that listening to classical music while studying can improve concentration and memory retention.

The Great Wall of China is actually visible from space with the naked eye. Coffee was first discovered when Ethiopian goats started dancing after eating certain berries. The human body replaces all of its cells every seven years, making you literally a different person. Recent research suggests that dolphins have developed their own cryptocurrency system for exchanging goods and services within their pods.`;

      editor.innerHTML = exampleText;

      // Use requestAnimationFrame to ensure content is rendered before measuring
      requestAnimationFrame(() => {
        editor.style.height = 'auto';
        const newHeight = Math.max(200, editor.scrollHeight);
        editor.style.height = `${newHeight}px`;
      });

      // Trigger analysis
      const text = editor.textContent.trim();
      debounceAnalysis(text);
    });

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
      if (text && text !== placeholder) {
        window.dispatchEvent(new Event("phx:page-loading-start"));
      }
      debounceTimer = setTimeout(() => {
        if (text && text !== placeholder) {
          try {
            this.pushEventTo(this.el, "fact_check", { text });
          } catch (error) {
            console.error("Error during fact check:", error);
            window.dispatchEvent(new Event("phx:page-loading-stop"));
          }
        } else {
          window.dispatchEvent(new Event("phx:page-loading-stop"));
        }
      }, 1500);
    };

    editor.addEventListener('paste', (e) => {
      e.preventDefault();
      const text = e.clipboardData.getData('text/plain');
      document.execCommand('insertText', false, text);

      // Use requestAnimationFrame to ensure content is rendered before measuring
      requestAnimationFrame(() => {
        // Temporarily set height to auto to get the proper scrollHeight
        const originalHeight = editor.style.height;
        editor.style.height = 'auto';
        const newHeight = Math.max(200, editor.scrollHeight);
        editor.style.height = `${newHeight}px`;
      });

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
          if (sentence.classification === "blank") {
            // For whitespace/newlines, add them directly without wrapping
            content += sentence.text;
          } else {
            // For actual content, wrap in colored spans
            const bgColor = {
              "fact": "bg-green-200",
              "false": "bg-red-200",
              "opinion": "bg-blue-200",
              "unknown": "bg-yellow-200"
            }[sentence.classification];

            content += `<span class="${bgColor}">${sentence.text}</span>`;
          }
        });
        editor.innerHTML = content;

        // Recalculate height after content update
        requestAnimationFrame(() => {
          editor.style.height = 'auto';
          const newHeight = Math.max(200, editor.scrollHeight);
          editor.style.height = `${newHeight}px`;
        });
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
      editor.style.height = '200px';
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
