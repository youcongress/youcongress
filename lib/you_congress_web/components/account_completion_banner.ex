defmodule YouCongressWeb.AccountCompletionBanner do
  use YouCongressWeb, :html

  alias YouCongress.Accounts
  alias YouCongress.Accounts.User
  alias YouCongressWeb.ReturnTo

  attr :current_user, :any, default: nil
  attr :return_to, :string, default: nil

  def account_completion_banner(%{current_user: %User{} = user} = assigns) do
    assigns =
      assigns
      |> assign(:show?, Accounts.account_completion_banner_needed?(user))
      |> assign(:phone_missing?, is_nil(user.phone_number_confirmed_at))
      |> assign(:newsletter_missing?, !user.newsletter)
      |> assign(:return_to, ReturnTo.sanitize(assigns.return_to))

    ~H"""
    <aside
      :if={@show?}
      id="account-completion-banner"
      class="border-b border-indigo-200 bg-indigo-50 px-4 py-3 text-sm text-indigo-950 sm:px-6 lg:px-8"
      aria-label="Optional account setup"
    >
      <div class="mx-auto flex max-w-7xl flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="font-semibold">Optional: finish setting up your account</p>
          <p class="mt-0.5 text-indigo-800">
            <span :if={@phone_missing?}>Verify your phone to help reduce spam</span>
            <%= if @newsletter_missing? do %>
              <span :if={@phone_missing?}> or </span>
              <span>subscribe to occasional YouCongress updates</span>
            <% end %>.
          </p>
        </div>

        <div class="flex shrink-0 flex-wrap items-center gap-2">
          <.link
            :if={@phone_missing?}
            href={~p"/account-completion/phone?#{%{return_to: @return_to}}"}
            class="rounded-md bg-indigo-600 px-3 py-1.5 font-semibold text-white hover:bg-indigo-500"
          >
            Verify phone
          </.link>
          <.link
            :if={@newsletter_missing?}
            href={~p"/account-completion/newsletter?#{%{return_to: @return_to}}"}
            method="post"
            class="rounded-md bg-white px-3 py-1.5 font-semibold text-indigo-700 ring-1 ring-inset ring-indigo-300 hover:bg-indigo-100"
          >
            Subscribe
          </.link>
          <.link
            href={~p"/account-completion/dismiss?#{%{return_to: @return_to}}"}
            method="post"
            class="rounded-md p-1.5 text-indigo-700 hover:bg-indigo-100"
            aria-label="Dismiss account setup reminder"
          >
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </.link>
        </div>
      </div>
    </aside>
    """
  end

  def account_completion_banner(assigns) do
    ~H"""
    """
  end
end
