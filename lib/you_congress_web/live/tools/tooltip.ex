defmodule YouCongressWeb.Tools.Tooltip do
  @moduledoc """
  Provides tooltip component.
  Adapted from Phoenix UI https://github.com/keatz55/phoenix_ui
  """
  use Phoenix.Component

  alias YouCongressWeb.Tools.Tooltip

  @default_color "slate"
  @default_position "top"
  @default_variant "simple"

  def delegation(assigns) do
    ~H"""
    <Tooltip.render
      content={[
        "Choose a list of delegates",
        "to vote as the majority of them.",
        "Unless you vote directly."
      ]}
      position="left"
    >
      <img src="/images/info.svg" alt="Info" class="h-4 w-4 inline" />
    </Tooltip.render>
    """
  end

  @doc """
  Renders tooltip component.

  ## Examples

      ```
      <.tooltip>
        content
      </.tooltip>
      ```

  """
  @spec render(Socket.assigns()) :: Rendered.t()
  def render(raw) do
    assigns =
      raw
      |> assign_new(:color, fn -> @default_color end)
      |> assign_new(:position, fn -> @default_position end)
      |> assign_new(:variant, fn -> @default_variant end)
      |> build_tooltip_attrs()

    ~H"""
    <div id={assigns[:id]} class="group relative inline-block pr-2">
      <%= render_slot(@inner_block) %>
      <div {@tooltip_attrs}>
        <%= cond do %>
          <% is_list(@content) -> %>
            <%= Enum.map(@content, fn line -> %>
              <div><%= line %></div>
            <% end) %>
          <% is_bitstring(@content) -> %>
            <%= @content %>
          <% true -> %>
            <%= render_slot(@content) %>
        <% end %>
      </div>
    </div>
    """
  end

  ### Tooltip Attrs ##########################

  defp build_tooltip_attrs(assigns) do
    class = [
      "bg-slate-800 text-slate-200 z-50 invisible opacity-0 group-hover:visible group-hover:opacity-100 absolute text-sm rounded text-center whitespace-nowrap py-1 px-2 transition-all ease-in-out delay-150 duration-300",
      classes(:margin, assigns),
      classes(:position, assigns),
      classes(:variant, assigns),
      Map.get(assigns, :extend_class)
    ]

    attrs =
      assigns
      |> assigns_to_attributes([:content, :id, :position, :variant])
      |> Keyword.put_new(:class, class)

    assign(assigns, :tooltip_attrs, attrs)
  end

  ### CSS Classes ##########################

  # Margin
  defp classes(:margin, %{position: "bottom_end"}), do: "mt-3"
  defp classes(:margin, %{position: "bottom_start"}), do: "mt-3"
  defp classes(:margin, %{position: "bottom"}), do: "mt-3"
  defp classes(:margin, %{position: "left_end"}), do: "mr-3"
  defp classes(:margin, %{position: "left_start"}), do: "mr-3"
  defp classes(:margin, %{position: "left"}), do: "mr-3"
  defp classes(:margin, %{position: "right_end"}), do: "ml-3"
  defp classes(:margin, %{position: "right_start"}), do: "ml-3"
  defp classes(:margin, %{position: "right"}), do: "ml-3"
  defp classes(:margin, %{position: "top_end"}), do: "mb-3"
  defp classes(:margin, %{position: "top_start"}), do: "mb-3"
  defp classes(:margin, %{position: "top"}), do: "mb-3"

  # Position
  defp classes(:position, %{position: "bottom_end"}), do: "top-full right-0"
  defp classes(:position, %{position: "bottom_start"}), do: "top-full left-0"
  defp classes(:position, %{position: "bottom"}), do: "top-full left-1/2 -translate-x-1/2"
  defp classes(:position, %{position: "left_end"}), do: "right-full bottom-0"
  defp classes(:position, %{position: "left_start"}), do: "right-full top-0"
  defp classes(:position, %{position: "left"}), do: "right-full top-1/2 -translate-y-1/2"
  defp classes(:position, %{position: "right_end"}), do: "left-full bottom-0"
  defp classes(:position, %{position: "right_start"}), do: "left-full top-0"
  defp classes(:position, %{position: "right"}), do: "left-full top-1/2 -translate-y-1/2"
  defp classes(:position, %{position: "top_end"}), do: "bottom-full right-0"
  defp classes(:position, %{position: "top_start"}), do: "bottom-full left-0"

  defp classes(:position, %{position: "top"}),
    do: "bottom-full left-0"

  # Variant
  defp classes(:variant, %{position: position, variant: "arrow"}) do
    case position do
      pos when pos in ["bottom_end", "bottom_start", "bottom"] ->
        "after:absolute after:-top-1.5 after:left-1/2 after:-translate-x-1/2 after:border-solid after:border-b-8 after:border-x-transparent after:border-x-8 after:border-t-0 after:border-b-slate-800"

      pos when pos in ["left_end", "left_start", "left"] ->
        "after:absolute after:-right-1.5 after:top-1/2 after:-translate-y-1/2 after:border-solid after:border-l-8 after:border-y-transparent after:border-y-8 after:border-r-0 after:border-l-slate-800"

      pos when pos in ["right_end", "right_start", "right"] ->
        "after:absolute after:-left-1.5 after:top-1/2 after:-translate-y-1/2 after:border-solid after:border-r-8 after:border-y-transparent after:border-y-8 after:border-l-0 after:border-r-slate-800"

      pos when pos in ["top_end", "top_start", "top"] ->
        "after:absolute after:-bottom-1.5 after:left-1/2 after:-translate-x-1/2 after:border-solid after:border-t-8 after:border-x-transparent after:border-x-8 after:border-b-0 after:border-t-slate-800"
    end
  end

  defp classes(_rule_group, _assigns), do: nil
end
