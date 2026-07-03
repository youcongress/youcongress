defmodule YouCongress.Opinions.Opinion do
  @moduledoc """
  The schema for opinions/c/quotes.
  """

  use Ecto.Schema
  use Ancestry, repo: YouCongress.Repo

  import Ecto.Changeset

  @date_precisions [:day, :month, :year]

  schema "opinions" do
    field :source_url, :string
    field :source_text, :string
    field :content, :string
    field :content_embedding, Pgvector.Ecto.Vector
    field :similarity, :float, virtual: true
    field :twin, :boolean, default: false

    field :verification_status, Ecto.Enum,
      values: [:verified, :ai_verified, :ai_unverifiable, :endorsed, :disputed, :unverifiable]

    field :ancestry, :string
    field :descendants_count, :integer, default: 0
    field :likes_count, :integer, default: 0
    field :date, :date
    field :date_precision, Ecto.Enum, values: @date_precisions

    belongs_to :author, YouCongress.Authors.Author
    belongs_to :user, YouCongress.Accounts.User
    has_many :verifications, YouCongress.Verifications.Verification
    has_many :opinion_statements, YouCongress.OpinionsStatements.OpinionStatement

    many_to_many(
      :statements,
      YouCongress.Statements.Statement,
      join_through: "opinions_statements",
      join_keys: [opinion_id: :id, statement_id: :id],
      on_replace: :delete
    )

    has_many :likes, YouCongress.Likes.Like

    timestamps()
  end

  @doc false
  def changeset(opinion, attrs) do
    attrs = normalize_date_attrs(attrs)

    opinion
    |> cast(attrs, [
      :content,
      :content_embedding,
      :source_url,
      :source_text,
      :twin,
      :verification_status,
      :author_id,
      :user_id,
      :ancestry,
      :descendants_count,
      :likes_count,
      :date,
      :date_precision
    ])
    |> validate_required([:content, :twin])
    |> default_date_precision()
    |> truncate_date_to_precision()
    |> validate_date_pair()
    |> validate_source_url_if_present()
  end

  def date_precisions, do: @date_precisions

  @doc """
  Returns true when the opinion is a quote, i.e. it carries a source. A source can be
  either a web URL (`source_url`) or a free-text passage from a non-web source such as a
  book, PDF, or paywalled article (`source_text`).
  """
  def quote?(%{source_url: source_url, source_text: source_text}),
    do: not (is_nil(source_url) and is_nil(source_text))

  def quote?(_), do: false

  @doc """
  Returns true when the opinion has a linkable/fetchable web source URL.
  """
  def has_source_url?(%{source_url: source_url}), do: is_binary(source_url) and source_url != ""
  def has_source_url?(_), do: false

  def display_date(%{date: nil}), do: nil
  def display_date(%{date: %Date{} = date, date_precision: :year}), do: pad_year(date.year)

  def display_date(%{date: %Date{} = date, date_precision: :month}) do
    Calendar.strftime(date, "%b %Y")
  end

  def display_date(%{date: %Date{} = date}) do
    Calendar.strftime(date, "%b #{date.day}, %Y")
  end

  def date_iso(%{date: %Date{} = date}), do: Date.to_iso8601(date)
  def date_iso(_), do: nil

  def date_precision_string(%{date_precision: nil}), do: nil
  def date_precision_string(%{date_precision: precision}) when is_binary(precision), do: precision
  def date_precision_string(%{date_precision: precision}), do: Atom.to_string(precision)

  def date_year(%{date: %Date{year: year}}), do: year
  def date_year(_), do: nil

  def serialized_date_fields(opinion) do
    %{
      date: date_iso(opinion),
      date_precision: date_precision_string(opinion)
    }
  end

  defp normalize_date_attrs(attrs) when is_map(attrs) do
    attrs
    |> stringify_keys()
    |> normalize_legacy_year()
    |> normalize_date_value()
  end

  defp normalize_date_attrs(attrs), do: attrs

  defp stringify_keys(attrs) do
    Map.new(attrs, fn {key, value} ->
      key =
        if is_atom(key) do
          Atom.to_string(key)
        else
          key
        end

      {key, value}
    end)
  end

  defp normalize_legacy_year(%{"date" => date} = attrs) when date not in [nil, ""], do: attrs

  defp normalize_legacy_year(%{"year" => year} = attrs) when year not in [nil, ""] do
    case parse_year(year) do
      {:ok, year} ->
        attrs
        |> Map.put("date", "#{pad_year(year)}-01-01")
        |> Map.put_new("date_precision", "year")

      :error ->
        attrs
        |> Map.put("date", "#{year}-01-01")
        |> Map.put_new("date_precision", "year")
    end
  end

  defp normalize_legacy_year(attrs), do: attrs

  defp normalize_date_value(%{"date" => date} = attrs) when is_binary(date) do
    date = String.trim(date)

    cond do
      Regex.match?(~r/^\d{4}$/, date) ->
        attrs
        |> Map.put("date", "#{date}-01-01")
        |> put_default_precision("year")

      Regex.match?(~r/^\d{4}-\d{2}$/, date) ->
        attrs
        |> Map.put("date", "#{date}-01")
        |> put_default_precision("month")

      date == "" ->
        attrs

      true ->
        put_default_precision(attrs, "day")
    end
  end

  defp normalize_date_value(%{"date" => %Date{}} = attrs), do: put_default_precision(attrs, "day")
  defp normalize_date_value(attrs), do: attrs

  defp put_default_precision(%{"date_precision" => precision} = attrs, _default)
       when precision not in [nil, ""],
       do: attrs

  defp put_default_precision(attrs, default), do: Map.put(attrs, "date_precision", default)

  defp parse_year(year) when is_integer(year) and year >= 1 and year <= 9999, do: {:ok, year}

  defp parse_year(year) when is_binary(year) do
    year = String.trim(year)

    case Integer.parse(year) do
      {year, ""} when year >= 1 and year <= 9999 -> {:ok, year}
      _ -> :error
    end
  end

  defp parse_year(_), do: :error

  defp default_date_precision(changeset) do
    if get_field(changeset, :date) && is_nil(get_field(changeset, :date_precision)) do
      put_change(changeset, :date_precision, :day)
    else
      changeset
    end
  end

  defp truncate_date_to_precision(changeset) do
    date = get_field(changeset, :date)

    case {date, get_field(changeset, :date_precision)} do
      {%Date{} = date, :year} -> put_change(changeset, :date, %{date | month: 1, day: 1})
      {%Date{} = date, :month} -> put_change(changeset, :date, %{date | day: 1})
      _ -> changeset
    end
  end

  defp validate_date_pair(changeset) do
    date = get_field(changeset, :date)
    precision = get_field(changeset, :date_precision)

    cond do
      is_nil(date) and is_nil(precision) -> changeset
      is_nil(date) -> add_error(changeset, :date, "can't be blank")
      is_nil(precision) -> add_error(changeset, :date_precision, "can't be blank")
      true -> changeset
    end
  end

  defp pad_year(year), do: year |> Integer.to_string() |> String.pad_leading(4, "0")

  defp validate_source_url_if_present(changeset) do
    case get_field(changeset, :source_url) do
      nil ->
        changeset

      source_url ->
        if starts_with_http(source_url) do
          changeset
        else
          add_error(changeset, :source_url, "is not a valid URL")
        end
    end
  end

  defp starts_with_http("http://" <> _), do: true
  defp starts_with_http("https://" <> _), do: true
  defp starts_with_http(_), do: false

  def path_str(%{ancestry: nil, id: id}), do: "#{id}"
  def path_str(%{ancestry: ancestry, id: id}), do: "#{ancestry}/#{id}"

  @doc """
  Gets the first statement for an opinion (replacement for primary_statement).
  """
  def first_statement(%{statements: [statement | _]}) when not is_nil(statement), do: statement
  def first_statement(_), do: nil

  @doc """
  Returns true if the opinion has a verification status set.
  """
  def verified?(%{verification_status: nil}), do: false
  def verified?(%{verification_status: status}) when not is_nil(status), do: true
  def verified?(_), do: false
end
