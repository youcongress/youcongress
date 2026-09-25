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
      |> assign(:prompt, Accounts.account_completion_prompt(user))
      |> assign(:return_to, ReturnTo.sanitize(assigns.return_to))

    ~H"""
    <aside
      :if={@prompt}
      id="account-completion-banner"
      class="border-b border-indigo-200 bg-indigo-50 px-4 py-3 text-sm text-indigo-950 sm:px-6 lg:px-8"
      aria-label="Optional account setup"
    >
      <div class="mx-auto flex max-w-7xl flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wide text-indigo-600">
            Optional · {if @prompt == :phone, do: "1/2", else: "2/2"}
          </p>
          <p class="font-semibold">
            {if @prompt == :phone,
              do: "Verify your phone",
              else: "Get occasional YouCongress updates"}
          </p>
          <p :if={@prompt == :phone} class="mt-0.5 text-indigo-800">
            Phone verification helps reduce spam and abuse.
          </p>
          <p :if={@prompt == :newsletter} class="mt-0.5 text-indigo-800">
            Subscribe to occasional news and product updates.
          </p>
        </div>

        <div class="flex shrink-0 flex-wrap items-center gap-2">
          <.link
            :if={@prompt == :phone}
            href={~p"/account-completion/phone?#{%{return_to: @return_to}}"}
            class="rounded-md bg-indigo-600 px-3 py-1.5 font-semibold text-white hover:bg-indigo-500"
          >
            Verify phone
          </.link>
          <.link
            :if={@prompt == :newsletter}
            href={~p"/account-completion/newsletter?#{%{return_to: @return_to}}"}
            method="post"
            class="rounded-md bg-white px-3 py-1.5 font-semibold text-indigo-700 ring-1 ring-inset ring-indigo-300 hover:bg-indigo-100"
          >
            Subscribe
          </.link>
          <.link
            href={dismiss_path(@prompt, @return_to)}
            method="post"
            class="rounded-md px-3 py-1.5 font-semibold text-indigo-700 hover:bg-indigo-100"
          >
            Not now
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

  defp dismiss_path(:phone, return_to) do
    ~p"/account-completion/dismiss-phone?#{%{return_to: return_to}}"
  end

  defp dismiss_path(:newsletter, return_to) do
    ~p"/account-completion/dismiss-newsletter?#{%{return_to: return_to}}"
  end
end
