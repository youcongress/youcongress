defmodule YouCongressWeb.SEOComponents do
  @moduledoc """
  Components for SEO/structured-data markup.
  """
  use Phoenix.Component

  @doc """
  Renders a schema.org JSON-LD script tag. Valid anywhere in the document,
  so pages can render it in their own template instead of the layout head.
  """
  attr :data, :map, required: true

  # HTML-safe JSON escapes <, &, and script-closing sequences before raw insertion.
  # sobelow_skip ["XSS.Raw"]
  def json_ld(assigns) do
    ~H"""
    <script type="application/ld+json">
      <%= Phoenix.HTML.raw(Jason.encode!(@data, escape: :html_safe)) %>
    </script>
    """
  end
end
