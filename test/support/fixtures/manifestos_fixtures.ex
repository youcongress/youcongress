defmodule YouCongress.ManifestosFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Manifestos` context.
  """

  def unique_manifesto_slug, do: "manifesto-#{System.unique_integer([:positive])}"

  def manifesto_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || YouCongress.AccountsFixtures.user_fixture().id

    {:ok, manifesto} =
      attrs
      |> Enum.into(%{
        title: "some title",
        slug: unique_manifesto_slug(),
        active: true,
        user_id: user_id
      })
      |> YouCongress.Manifestos.create_manifesto()

    manifesto
  end

  def manifesto_section_fixture(attrs \\ %{}) do
    {:ok, section} =
      attrs
      |> Enum.into(%{
        body: "some body",
        weight: 0,
        manifesto_id: attrs[:manifesto_id]
      })
      |> YouCongress.Manifestos.create_section()

    section
  end
end
