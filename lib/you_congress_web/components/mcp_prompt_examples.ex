defmodule YouCongressWeb.Components.McpPromptExamples do
  @moduledoc """
  Shared prompt examples for MCP-related pages.
  """

  use Phoenix.Component

  slot :intro,
    required: true,
    doc: "Paragraph displayed above the sample prompts."

  slot :permission_notice,
    required: true,
    doc: "Paragraph reminding users how the AI assistant uses tools."

  def prompt_examples(assigns) do
    ~H"""
    <p class="mt-4 text-lg leading-relaxed">
      {render_slot(@intro)}
    </p>

    <div class="mt-4 space-y-4">
      <div class="p-4 bg-gray-50 rounded-lg border border-gray-200">
        <div class="flex items-start justify-between gap-4">
          <p id="claude-prompt-1" class="flex-1 text-base text-gray-800 italic">
            You are a policy analyst researching AI's impact on jobs. Use YouCongress to search quotes from 2025 onwards, cluster them by argument, create a disagreement map and identify tension points. Return verbatim attributed quotes with links to sources.
          </p>
          <button
            type="button"
            class="ml-4 shrink-0 text-gray-500 hover:text-gray-800 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-500"
            data-copy-target="claude-prompt-1"
            aria-label="Copy prompt"
          >
            <span class="sr-only">Copy prompt</span>
            <svg
              class="h-5 w-5"
              viewBox="0 0 24 24"
              role="img"
              aria-hidden="true"
              fill="none"
              stroke="currentColor"
              stroke-width="1.6"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <rect x="9" y="9" width="11" height="11" rx="2" />
              <path d="M5 15V5a2 2 0 0 1 2-2h10" />
            </svg>
          </button>
        </div>
      </div>
      <div class="p-4 bg-gray-50 rounded-lg border border-gray-200">
        <div class="flex items-start justify-between gap-4">
          <p id="claude-prompt-2" class="flex-1 text-base text-gray-800 italic">
            You're a journalist writing about the pros and cons of advanced open source AI. Use YouCongress, identify arguments, explain each of them and include alternative policies. Return verbatim quotes with links to the sources.
          </p>
          <button
            type="button"
            class="ml-4 shrink-0 text-gray-500 hover:text-gray-800 transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-500"
            data-copy-target="claude-prompt-2"
            aria-label="Copy prompt"
          >
            <span class="sr-only">Copy prompt</span>
            <svg
              class="h-5 w-5"
              viewBox="0 0 24 24"
              role="img"
              aria-hidden="true"
              fill="none"
              stroke="currentColor"
              stroke-width="1.6"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <rect x="9" y="9" width="11" height="11" rx="2" />
              <path d="M5 15V5a2 2 0 0 1 2-2h10" />
            </svg>
          </button>
        </div>
      </div>
    </div>

    <p class="mt-4 text-lg leading-relaxed">
      {render_slot(@permission_notice)}
    </p>
    """
  end
end
