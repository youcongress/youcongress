defmodule YouCongressWeb.Components.FooterComponent do
  @moduledoc """
  The footer component.
  """

  use Phoenix.Component
  use YouCongressWeb, :html

  def footer(assigns) do
    ~H"""
    <div class="text-center pb-4 text-sm">
      <.link href="https://github.com/youcongress/youcongress" target="_blank">GitHub</.link>
      · <.link href="https://web.telegram.org/a/#-1002011576166" target="_blank">Telegram</.link>
      · <.link href={~p"/terms"}>Terms</.link>
      · <.link href={~p"/privacy-policy"}>Privacy</.link>
      · <.link href="mailto:hi@youcongress.com">Contact</.link>
    </div>
    """
  end
end
