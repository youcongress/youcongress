defmodule YouCongressWeb.PeopleListPaths do
  @moduledoc "Canonical public list addresses, with an author-ID fallback until a username is chosen."
  use YouCongressWeb, :verified_routes

  def public_path(list) do
    owner = YouCongress.Repo.get!(YouCongress.Authors.Author, list.author_id)
    public_path(owner, list.slug)
  end

  def public_path(%{username: username}, slug) when is_binary(username) and username != "",
    do: ~p"/@#{username}/lists/#{slug}"

  def public_path(owner, slug), do: ~p"/a/#{owner.id}/lists/#{slug}"
  def public_url(owner, slug), do: YouCongressWeb.Endpoint.url() <> public_path(owner, slug)

  def edit_fields(draft, params, custom?, author_id) do
    name = Map.get(params, "name", draft.name)

    custom? =
      custom? || params["_target"] == ["slug"] ||
        (is_nil(params["_target"]) && params["slug"] not in [nil, ""] &&
           params["slug"] != draft.slug)

    slug =
      if custom?,
        do: Map.get(params, "slug", draft.slug),
        else: YouCongress.PeopleLists.suggest_slug(author_id, name)

    {%{draft | name: name, slug: slug}, custom?}
  end

  def slug_error(%Ecto.Changeset{errors: errors}) do
    case Keyword.get(errors, :slug) do
      nil ->
        nil

      {message, options} ->
        Enum.reduce(options, message, fn {key, value}, text ->
          String.replace(text, "%{#{key}}", to_string(value))
        end)
    end
  end
end
