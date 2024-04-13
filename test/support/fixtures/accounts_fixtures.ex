defmodule YouCongress.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `YouCongress.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    attrs
    |> ensure_keys_are_strings()
    |> Enum.into(%{
      "email" => unique_user_email(),
      "password" => valid_user_password()
    })
  end

  @spec ensure_keys_are_strings(map) :: map
  defp ensure_keys_are_strings(attrs) do
    Enum.map(attrs, fn {k, v} -> {to_string(k), v} end)
  end

  def user_fixture(attrs \\ %{}, author_attrs \\ nil) do
    author_attrs =
      author_attrs ||
        %{
          name: Faker.Person.name(),
          twitter_username: Faker.Internet.user_name(),
          bio: Faker.Lorem.sentence(),
          wikipedia_url: "https://wikipedia.org/wiki/#{Faker.Internet.user_name()}",
          twin_origin: false
        }

    {:ok, %{user: user}} =
      attrs
      |> valid_user_attributes()
      |> YouCongress.Accounts.register_user(author_attrs)

    user
  end

  def admin_fixture(attrs \\ %{}, author_attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> user_fixture(author_attrs)
      |> YouCongress.Accounts.update_role("admin")

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
