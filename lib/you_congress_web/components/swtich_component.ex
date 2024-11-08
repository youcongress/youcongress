defmodule YouCongressWeb.Components.SwitchComponent do
  use Phoenix.Component

  attr :order_by_date, :boolean
  attr :label1, :string
  attr :label2, :string

  def render(assigns) do
    ~H"""
    <div class="text-gray-600 pt-3 text-xs">
      <%= @label1 %>
    </div>
    <div class="pt-2 px-1">
      <button
        type="button"
        phx-click="toggle-order-by-date"
        class={[
          @order_by_date && "bg-indigo-600",
          !@order_by_date && "bg-gray-200",
          "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent bg-gray-200 transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-indigo-600 focus:ring-offset-2"
        ]}
        role="switch"
        aria-checked="false"
      >
        <span class="sr-only">Use setting</span>
        <span
          aria-hidden="true"
          class={[
            @order_by_date && "translate-x-5",
            !@order_by_date && "translate-x-0",
            "pointer-events-none inline-block h-5 w-5 translate-x-0 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"
          ]}
        >
        </span>
      </button>
    </div>
    <div class="text-gray-600 pt-3 text-xs pr-2">
      <%= @label2 %>
    </div>
    """
  end
end
