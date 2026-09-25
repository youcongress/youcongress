defmodule YouCongressWeb.Components.FooterComponent do
  @moduledoc """
  The footer component.
  """

  use Phoenix.Component
  use YouCongressWeb, :html

  def footer(assigns) do
    ~H"""
    <footer class="text-center pb-10 text-sm">
      <.link href={~p"/terms"}>Terms</.link>
      · <.link href={~p"/privacy-policy"}>Privacy</.link>
      · <button type="button" data-cookie-settings class="hover:underline">Cookie settings</button>
      · <.link href="mailto:hello@youcongress.org" target="_blank">Contact</.link>
    </footer>
    """
  end
end
