defmodule YouCongress.OpinionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Opinions` context.
  """

  @doc """
  Generate a opinion.
  """
  def opinion_fixture(attrs \\ %{}) do
    {:ok, opinion} =
      attrs
      |> Enum.into(%{
        content: "some content",
        source_url: "some source_url",
        twin: true
      })
      |> YouCongress.Opinions.create_opinion()

    opinion
  end
end
