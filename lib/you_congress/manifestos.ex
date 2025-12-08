defmodule YouCongress.Manifestos do
  @moduledoc """
  The Manifestos context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Manifestos.Manifesto
  alias YouCongress.Manifestos.ManifestoSection
  alias YouCongress.Manifestos.ManifestoSignature
  alias YouCongress.Votes

  @doc """
  Returns the list of manifestos.
  """
  def list_manifestos do
    Repo.all(Manifesto)
  end

  @doc """
  Returns the list of active manifestos.
  """
  def list_active_manifestos do
    from(m in Manifesto, where: m.active == true)
    |> Repo.all()
  end

  @doc """
  Gets a single manifesto.
  """
  def get_manifesto!(id), do: Repo.get!(Manifesto, id)

  @doc """
  Gets a single manifesto by slug, preloading sections and signatures count.
  """
  def get_manifesto_by_slug!(slug) do
    Repo.get_by!(Manifesto, slug: slug)
    |> Repo.preload([:user, sections: [:voting]])
    |> Repo.preload(user: :author)
  end

  def get_manifesto_by_slug(slug) do
    Repo.get_by(Manifesto, slug: slug)
    |> Repo.preload(sections: [:voting])
  end

  @doc """
  Creates a manifesto.
  """
  def create_manifesto(attrs \\ %{}) do
    %Manifesto{}
    |> Manifesto.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a manifesto.
  """
  def update_manifesto(%Manifesto{} = manifesto, attrs) do
    manifesto
    |> Manifesto.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a manifesto.
  """
  def delete_manifesto(%Manifesto{} = manifesto) do
    Repo.delete(manifesto)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking manifesto changes.
  """
  def change_manifesto(%Manifesto{} = manifesto, attrs \\ %{}) do
    Manifesto.changeset(manifesto, attrs)
  end

  @doc """
  Creates a manifesto section.
  """
  def create_section(attrs \\ %{}) do
    %ManifestoSection{}
    |> ManifestoSection.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a manifesto section.
  """
  def update_section(%ManifestoSection{} = section, attrs) do
    section
    |> ManifestoSection.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a manifesto section.
  """
  def delete_section(%ManifestoSection{} = section) do
    Repo.delete(section)
  end

  @doc """
  Returns a section by id.
  """
  def get_section!(id), do: Repo.get!(ManifestoSection, id)

  @doc """
  Signs a manifesto for a user and casts votes for linked motions.
  """
  def sign_manifesto(%Manifesto{} = manifesto, %YouCongress.Accounts.User{} = user) do
    # Ensure all associations are loaded
    manifesto = Repo.preload(manifesto, :sections)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:signature, fn _changes ->
      %ManifestoSignature{}
      |> ManifestoSignature.changeset(%{manifesto_id: manifesto.id, user_id: user.id})
    end)
    |> Ecto.Multi.run(:votes, fn repo, _changes ->
      results =
        for section <- manifesto.sections, section.voting_id do
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
  def signed?(%Manifesto{} = manifesto, %YouCongress.Accounts.User{} = user) do
    Repo.exists?(from s in ManifestoSignature, where: s.manifesto_id == ^manifesto.id and s.user_id == ^user.id)
  end

  @doc """
  Unsigned a manifesto for a user. Removes the ManifestoSignature.
  """
  def unsign_manifesto(%Manifesto{} = manifesto, %YouCongress.Accounts.User{} = user) do
    case Repo.get_by(ManifestoSignature, manifesto_id: manifesto.id, user_id: user.id) do
      nil -> {:error, :not_signed}
      signature -> Repo.delete(signature)
    end
  end

  def signatures_count(%Manifesto{} = manifesto) do
    Repo.aggregate(from(s in ManifestoSignature, where: s.manifesto_id == ^manifesto.id), :count, :id)
  end


end
