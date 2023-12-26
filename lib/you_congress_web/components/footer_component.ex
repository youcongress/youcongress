defmodule YouCongressWeb.Components.FooterComponent do
  @moduledoc """
  The footer component.
  """

  use Phoenix.Component
  use YouCongressWeb, :html

  def footer(assigns) do
    ~H"""
    <div class="text-center pb-4">
      <.link href={~p"/terms"} class="text-sm">Terms</.link>
      · <.link href={~p"/privacy-policy"} class="text-sm">Privacy</.link>
    </div>
    """
  end
end
