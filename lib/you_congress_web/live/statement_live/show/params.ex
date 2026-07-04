defmodule YouCongressWeb.StatementLive.Show.Params do
  @moduledoc false

  use Ecto.Schema

  alias YouCongress.Votes.VoteFrequencies

  @filter_keys [:direct, :delegated, :quotes, :email_verified, :phone_verified]
  @country_filter_fields Enum.map(@filter_keys, &String.to_atom("country_#{&1}"))
  @year_filter_fields Enum.map(@filter_keys, &String.to_atom("year_#{&1}"))
  @simple_fields [:synthesis, :results, :source, :answer] ++
                   @country_filter_fields ++ @year_filter_fields

  @derive {
    Flop.Schema,
    filterable: @simple_fields, sortable: []
  }
  @primary_key false
  embedded_schema do
    field :synthesis, :boolean
    field :results, Ecto.Enum, values: [:country, :year]
    field :source, Ecto.Enum, values: [:quotes, :users, :all]
    field :answer, Ecto.Enum, values: [:for, :abstain, :against]

    field :country_direct, :boolean
    field :country_delegated, :boolean
    field :country_quotes, :boolean
    field :country_email_verified, :boolean
    field :country_phone_verified, :boolean

    field :year_direct, :boolean
    field :year_delegated, :boolean
    field :year_quotes, :boolean
    field :year_email_verified, :boolean
    field :year_phone_verified, :boolean
  end

  def defaults do
    %{
      show_synthesis: false,
      results: nil,
      source_filter: :quotes,
      answer_filter: nil,
      country_results_filters: VoteFrequencies.default_country_filters(),
      year_results_filters: VoteFrequencies.default_year_filters()
    }
  end

  def from_params(params) when is_map(params) do
    params
    |> normalize_simple_params()
    |> Flop.nest_filters(@simple_fields)
    |> Flop.validate(for: __MODULE__)
    |> case do
      {:ok, flop} -> apply_filters(flop.filters)
      {:error, _meta} -> defaults()
    end
  end

  def from_params(_params), do: defaults()

  def to_query(params) when is_map(params) do
    params
    |> normalize_state()
    |> encode_query_params()
  end

  def put(params, updates) when is_map(params) and is_map(updates) do
    params
    |> Map.merge(updates)
    |> normalize_state()
  end

  def toggle_source(%{source_filter: source_filter} = params, source) do
    source_filter =
      case {source_filter, source} do
        {nil, :quotes} -> :quotes
        {:quotes, :quotes} -> nil
        {:users, :quotes} -> :quotes
        {nil, :users} -> :users
        {:quotes, :users} -> :users
        {:users, :users} -> nil
      end

    put(params, %{source_filter: source_filter})
  end

  def toggle_answer(params, ""), do: put(params, %{answer_filter: nil})
  def toggle_answer(params, nil), do: put(params, %{answer_filter: nil})
  def toggle_answer(params, answer), do: put(params, %{answer_filter: normalize_answer(answer)})

  defp apply_filters(filters) do
    Enum.reduce(filters, defaults(), fn
      %Flop.Filter{field: :synthesis, value: value}, params ->
        put(params, %{show_synthesis: value == true})

      %Flop.Filter{field: :results, value: value}, params ->
        put(params, %{results: normalize_results(value)})

      %Flop.Filter{field: :source, value: value}, params ->
        put(params, %{source_filter: source_filter(value)})

      %Flop.Filter{field: :answer, value: value}, params ->
        put(params, %{answer_filter: normalize_answer(value)})

      %Flop.Filter{field: field, value: value}, params ->
        apply_filter_field(params, field, value)
    end)
  end

  defp apply_filter_field(params, field, value) when is_boolean(value) do
    field
    |> filter_field()
    |> case do
      {:country, filter} ->
        put_in(params, [:country_results_filters, filter], value)

      {:year, filter} ->
        put_in(params, [:year_results_filters, filter], value)

      nil ->
        params
    end
  end

  defp apply_filter_field(params, _field, _value), do: params

  defp normalize_simple_params(params) do
    params
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      key = to_string(key)
      value = normalize_param_value(key, value)

      if key in Enum.map(@simple_fields, &to_string/1) and present?(value) do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  defp normalize_param_value("answer", value), do: answer_param(value)
  defp normalize_param_value(_key, value), do: value

  defp present?(value), do: value not in [nil, ""]

  defp normalize_state(params) do
    defaults()
    |> Map.merge(params)
    |> Map.update!(:results, &normalize_results/1)
    |> Map.update!(:source_filter, &normalize_source_filter/1)
    |> Map.update!(:answer_filter, &normalize_answer/1)
    |> Map.update!(:country_results_filters, &VoteFrequencies.normalize_country_filters/1)
    |> Map.update!(:year_results_filters, &VoteFrequencies.normalize_year_filters/1)
  end

  defp normalize_results(results) when results in [:country, "country"], do: :country
  defp normalize_results(results) when results in [:year, "year"], do: :year
  defp normalize_results(_), do: nil

  defp source_filter(:quotes), do: :quotes
  defp source_filter("quotes"), do: :quotes
  defp source_filter(:users), do: :users
  defp source_filter("users"), do: :users
  defp source_filter(:all), do: nil
  defp source_filter("all"), do: nil
  defp source_filter(_), do: :quotes

  defp normalize_source_filter(source_filter) when source_filter in [:quotes, :users, nil],
    do: source_filter

  defp normalize_source_filter("quotes"), do: :quotes
  defp normalize_source_filter("users"), do: :users
  defp normalize_source_filter("all"), do: nil
  defp normalize_source_filter(_), do: :quotes

  defp normalize_answer(answer) when answer in [:for, "for", "For"], do: "For"
  defp normalize_answer(answer) when answer in [:abstain, "abstain", "Abstain"], do: "Abstain"
  defp normalize_answer(answer) when answer in [:against, "against", "Against"], do: "Against"
  defp normalize_answer(_), do: nil

  defp encode_query_params(params) do
    %{}
    |> put_query(:synthesis, params.show_synthesis, "true")
    |> put_query(:results, params.results)
    |> put_source_query(params.source_filter)
    |> put_answer_query(params.answer_filter)
    |> put_filter_queries(:country, params.results, params.country_results_filters)
    |> put_filter_queries(:year, params.results, params.year_results_filters)
  end

  defp put_query(query, _key, false, _value), do: query
  defp put_query(query, key, true, value), do: Map.put(query, key, value)
  defp put_query(query, _key, nil), do: query
  defp put_query(query, key, value), do: Map.put(query, key, to_string(value))

  defp put_source_query(query, :quotes), do: query
  defp put_source_query(query, nil), do: Map.put(query, :source, "all")
  defp put_source_query(query, source), do: Map.put(query, :source, to_string(source))

  defp put_answer_query(query, nil), do: query
  defp put_answer_query(query, answer), do: Map.put(query, :answer, answer_param(answer))

  defp put_filter_queries(query, group, group, filters) do
    defaults = VoteFrequencies.default_country_filters()

    Enum.reduce(@filter_keys, query, fn filter, query ->
      if Map.get(filters, filter) == Map.get(defaults, filter) do
        query
      else
        Map.put(query, String.to_atom("#{group}_#{filter}"), to_string(Map.get(filters, filter)))
      end
    end)
  end

  defp put_filter_queries(query, _group, _active_group, _filters), do: query

  defp answer_param(answer) when answer in [:for, "for", "For"], do: "for"
  defp answer_param(answer) when answer in [:abstain, "abstain", "Abstain"], do: "abstain"
  defp answer_param(answer) when answer in [:against, "against", "Against"], do: "against"
  defp answer_param(answer), do: answer

  defp filter_field(field) do
    field = to_string(field)

    cond do
      String.starts_with?(field, "country_") ->
        {:country, String.replace_prefix(field, "country_", "") |> String.to_existing_atom()}

      String.starts_with?(field, "year_") ->
        {:year, String.replace_prefix(field, "year_", "") |> String.to_existing_atom()}

      true ->
        nil
    end
  rescue
    ArgumentError -> nil
  end
end
