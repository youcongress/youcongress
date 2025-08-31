defmodule YouCongress.Opinions.Replier.AIReplierBehaviour do
  @moduledoc """
  The behaviour for AI repliers.
  """

  alias YouCongress.Opinions.Opinion

  @callback maybe_reply(Opinion.t()) :: :ok
end
