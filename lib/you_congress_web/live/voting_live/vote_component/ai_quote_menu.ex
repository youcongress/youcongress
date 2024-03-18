defmodule YouCongressWeb.VotingLive.VoteComponent.AiQuoteMenu do
  @moduledoc """
  Displays links to:
  - About AI profiles
  - I am <%= @author_name %>
  - Add a real quote with a URL source
  """
  use Phoenix.Component

  attr :vote_id, :string, required: true
  attr :author_name, :string, required: true

  def render(assigns) do
    ~H"""
    <div class="justify-end" phx-hook="AIQuote" id={"ai-menu-#{@vote_id}"}>
      <button
        type="button"
        class="inline-flex items-center gap-x-1 text-sm font-semibold leading-6 text-gray-900"
        aria-expanded="false"
      >
        <svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24">
          <path d="M480-160q-33 0-56.5-23.5T400-240q0-33 23.5-56.5T480-320q33 0 56.5 23.5T560-240q0 33-23.5 56.5T480-160Zm0-240q-33 0-56.5-23.5T400-480q0-33 23.5-56.5T480-560q33 0 56.5 23.5T560-480q0 33-23.5 56.5T480-400Zm0-240q-33 0-56.5-23.5T400-720q0-33 23.5-56.5T480-800q33 0 56.5 23.5T560-720q0 33-23.5 56.5T480-640Z" />
        </svg>
      </button>
      <div class="opacity-0 absolute right-0 lg:right-0 z-10 lg:mt-5 flex lg:w-screen max-w-full lg:max-w-min lg:-translate-x-1/2 lg:px-1/2">
        <div class="w-56 shrink rounded-xl bg-white p-4 text-sm font-semibold leading-6 text-gray-900 shadow-lg ring-1 ring-gray-900/5">
          <a href="#" class="block p-2 hover:text-indigo-600">About AI profiles</a>
          <a href="#" class="block p-2 hover:text-indigo-600">I am <%= @author_name %></a>
          <a href="#" class="block p-2 hover:text-indigo-600">
            Add a real quote with a URL source (soon)
          </a>
        </div>
      </div>
    </div>
    """
  end
end
