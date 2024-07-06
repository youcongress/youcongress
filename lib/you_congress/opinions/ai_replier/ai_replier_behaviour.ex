defmodule YouCongress.Opinions.AIReplier.AIReplierBehaviour do
  @moduledoc """
  """

  alias YouCongress.Opinions.Opinion

  @callback maybe_reply(Opinion.t()) :: :ok
end
