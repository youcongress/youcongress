defmodule YouCongress.Manifests do
  @moduledoc """
  The Manifests context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Manifests.Manifest
  alias YouCongress.Manifests.ManifestSection
  alias YouCongress.Manifests.ManifestSignature
  alias YouCongress.Votes

  @doc """
  Returns the list of manifests.
  """
  def list_manifests do
    Repo.all(Manifest)
  end

  @doc """
  Returns the list of active manifests.
  """
  def list_active_manifests do
    from(m in Manifest, where: m.active == true)
    |> Repo.all()
  end

  @doc """
  Gets a single manifest.
  """
  def get_manifest!(id), do: Repo.get!(Manifest, id)

  @doc """
  Gets a single manifest by slug, preloading sections and signatures count.
  """
  def get_manifest_by_slug!(slug) do
    Repo.get_by!(Manifest, slug: slug)
    |> Repo.preload([:user, sections: [:voting]])
  end

  def get_manifest_by_slug(slug) do
    Repo.get_by(Manifest, slug: slug)
    |> Repo.preload(sections: [:voting])
  end

  @doc """
  Creates a manifest.
  """
  def create_manifest(attrs \\ %{}) do
    %Manifest{}
    |> Manifest.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a manifest.
  """
  def update_manifest(%Manifest{} = manifest, attrs) do
    manifest
    |> Manifest.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a manifest.
  """
  def delete_manifest(%Manifest{} = manifest) do
    Repo.delete(manifest)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking manifest changes.
  """
  def change_manifest(%Manifest{} = manifest, attrs \\ %{}) do
    Manifest.changeset(manifest, attrs)
  end

  @doc """
  Creates a manifest section.
  """
  def create_section(attrs \\ %{}) do
    %ManifestSection{}
    |> ManifestSection.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a manifest section.
  """
  def update_section(%ManifestSection{} = section, attrs) do
    section
    |> ManifestSection.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a manifest section.
  """
  def delete_section(%ManifestSection{} = section) do
    Repo.delete(section)
  end

  @doc """
  Returns a section by id.
  """
  def get_section!(id), do: Repo.get!(ManifestSection, id)

  @doc """
  Signs a manifest for a user and casts votes for linked motions.
  """
  def sign_manifest(%Manifest{} = manifest, %YouCongress.Accounts.User{} = user) do
    # Ensure all associations are loaded
    manifest = Repo.preload(manifest, :sections)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:signature, fn _changes ->
      %ManifestSignature{}
      |> ManifestSignature.changeset(%{manifest_id: manifest.id, user_id: user.id})
    end)
    |> Ecto.Multi.run(:votes, fn repo, _changes ->
      results =
        for section <- manifest.sections, section.voting_id do
          # Check if vote exists
          unless Votes.get_by(%{voting_id: section.voting_id, author_id: user.author_id}) do
            Votes.create_vote(%{
              voting_id: section.voting_id,
              author_id: user.author_id,
              answer: :for,
              direct: true
            })
          end
        end
      {:ok, results}
    end)
    |> Repo.transaction()
  end
  def signed?(%Manifest{} = manifest, %YouCongress.Accounts.User{} = user) do
    Repo.exists?(from s in ManifestSignature, where: s.manifest_id == ^manifest.id and s.user_id == ^user.id)
  end

  @doc """
  Unsigned a manifest for a user. Removes the ManifestSignature.
  """
  def unsign_manifest(%Manifest{} = manifest, %YouCongress.Accounts.User{} = user) do
    case Repo.get_by(ManifestSignature, manifest_id: manifest.id, user_id: user.id) do
      nil -> {:error, :not_signed}
      signature -> Repo.delete(signature)
    end
  end

  def signatures_count(%Manifest{} = manifest) do
    Repo.aggregate(from(s in ManifestSignature, where: s.manifest_id == ^manifest.id), :count, :id)
  end


end
