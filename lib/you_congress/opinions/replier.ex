defmodule YouCongress.Opinions.Replier do
  @moduledoc """
  Main entry point for opinion replier functionality.
  """

  alias YouCongress.Opinions.Replier.AIReplier

  def maybe_reply(opinion) do
    replier_implementation().maybe_reply(opinion)
  end

  defp replier_implementation do
    Application.get_env(:you_congress, :ai_replier, AIReplier)
  end
end
