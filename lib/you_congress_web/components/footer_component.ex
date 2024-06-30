defmodule YouCongressWeb.Components.FooterComponent do
  @moduledoc """
  The footer component.
  """

  use Phoenix.Component
  use YouCongressWeb, :html

  def footer(assigns) do
    ~H"""
    <div class="text-center pb-10 text-sm">
      <.link href={~p"/terms"}>Terms</.link>
      · <.link href={~p"/privacy-policy"}>Privacy</.link>
      · <.link href="mailto:hi@youcongress.com" target="_blank">Contact</.link>
    </div>
    """
  end
end
