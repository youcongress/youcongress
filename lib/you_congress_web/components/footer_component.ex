defmodule YouCongressWeb.Components.FooterComponent do
  use Phoenix.Component
  use YouCongressWeb, :html

  def footer(assigns) do
    ~H"""
    <div class="text-center">
      <.link href={~p"/terms"} class="text-sm">Terms</.link>
      · <.link href={~p"/privacy"} class="text-sm">Privacy</.link>
    </div>
    """
  end
end
