defmodule YouCongressWeb.Components.SwitchComponent do
  @moduledoc """
  A toggle switch component for Phoenix LiveView that allows users to switch between two states.
  """

  use Phoenix.Component

  attr :is_active, :boolean
  attr :label1, :string
  attr :label2, :string

  def render(assigns) do
    ~H"""
    <div class="inline-flex items-center gap-3 text-xs text-gray-600">
      <span class="leading-6 whitespace-nowrap">{@label1}</span>
      <button
        type="button"
        phx-click="toggle-switch"
        class={[
          @is_active && "bg-indigo-600",
          !@is_active && "bg-gray-200",
          "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent bg-gray-200 transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-indigo-600 focus:ring-offset-2"
        ]}
        role="switch"
        aria-checked={@is_active}
      >
        <span class="sr-only">Use setting</span>
        <span
          aria-hidden="true"
          class={[
            @is_active && "translate-x-5",
            !@is_active && "translate-x-0",
            "pointer-events-none inline-block h-5 w-5 translate-x-0 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"
          ]}
        >
        </span>
      </button>
      <span class="leading-6 whitespace-nowrap">{@label2}</span>
    </div>
    """
  end
end
