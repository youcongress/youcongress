defmodule YouCongressWeb.UserSignUpLive do
  use YouCongressWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <div class="text-center">
        <h1 class="text-2xl">Create a new account</h1>
        <div class="pt-2">
          Do you already have an account? <.link href="/log_in" class="underline">Log in</.link>
        </div>
      </div>

      <div class="text-center pt-6">
        <.link
          href="/x_log_in"
          method="post"
          class="inline-flex items-center justify-between bg-black text-white font-bold py-2 px-4 rounded-full hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-gray-600 focus:ring-opacity-50 transition-colors duration-300"
        >
          Sign in now with
          <svg
            class="w-5 h-5 ml-2"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="#ffffff"
          >
            <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
          </svg>
        </.link>*
      </div>
      <span class="text-xs">
        * If logging in with X fails, log in at
        <.link href="https://x.com" class="underline" target="_blank">x.com</.link>
        and then return here.
      </span>

      <p class="pt-4">
        To avoid spam and abuse, <strong>email/password login</strong>
        is currently <strong>disabled for free accounts</strong>.
      </p>
      <p class="pt-4 text-center">
        <.link
          href="/join-and-become-a-supporter"
          class="inline-block bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded-full"
        >
          Pay 25€ and get email/password access
        </.link>
      </p>
      <p class="pt-4">
        The one-time 25€ fee will provide you email/password access after payment confirmation. You will also get
        <strong>priority access to new features</strong>
        and become a key <strong>supporter of our
        open-source democracy
        project</strong>.
      </p>
      <p class="pt-4 text-center">
        <.link
          href="/email-login-waiting-list"
          class="inline-block bg-green-500 hover:bg-green-700 text-white font-bold py-2 px-4 rounded-full"
        >
          Join waiting list
        </.link>
      </p>
      <p class="pt-4">
        You can also join the waiting list and we'll let you know when you can join with email/password for free.
      </p>
    </div>
    """
  end
end
