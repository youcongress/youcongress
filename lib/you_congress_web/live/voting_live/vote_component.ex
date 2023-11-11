defmodule YouCongressWeb.VotingLive.VoteComponent do
  use YouCongressWeb, :live_component

  defp response(assigns, response) do
    assigns =
      assign(assigns, color: response_color(response), response: String.downcase(response))

    ~H"""
    <span class={"#{@color} font-bold"}>
      <%= @response %>
    </span>
    """
  end

  defp response_color("Agree"), do: "text-green-800"
  defp response_color("Strongly agree"), do: "text-green-800"
  defp response_color("Disagree"), do: "text-red-800"
  defp response_color("Strongly disagree"), do: "text-red-800"
  defp response_color("Abstain"), do: "text-gray-400"
  defp response_color("N/A"), do: "text-gray-400"
end
