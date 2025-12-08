defmodule YouCongress.ManifestsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Manifests` context.
  """

  def unique_manifest_slug, do: "manifest-#{System.unique_integer([:positive])}"

  def manifest_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || YouCongress.AccountsFixtures.user_fixture().id

    {:ok, manifest} =
      attrs
      |> Enum.into(%{
        title: "some title",
        slug: unique_manifest_slug(),
        active: true,
        user_id: user_id
      })
      |> YouCongress.Manifests.create_manifest()

    manifest
  end

  def manifest_section_fixture(attrs \\ %{}) do
    {:ok, section} =
      attrs
      |> Enum.into(%{
        body: "some body",
        weight: 0,
        manifest_id: attrs[:manifest_id]
      })
      |> YouCongress.Manifests.create_section()

    section
  end
end
