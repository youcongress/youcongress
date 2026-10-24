defmodule YouCongressWeb.StatementParamsTest do
  use ExUnit.Case, async: true

  alias YouCongressWeb.StatementLive.Show.Params

  test "all supported country and year filters round-trip using the existing keys" do
    for group <- [:country, :year],
        filter <- [:direct, :delegated, :quotes, :email_verified, :phone_verified] do
      key = "#{group}_#{filter}"
      input = %{"results" => to_string(group), key => "false"}
      state = Params.from_params(input)
      query = Params.to_query(state)

      assert query[:results] == to_string(group)
      assert Map.fetch!(query, String.to_existing_atom(key)) == "false"
      assert map_size(query) == 2
      assert Params.from_params(query) == state
    end
  end

  test "unknown and SQL-like inputs cannot create filter atoms or query keys" do
    unknown = "filter_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    state = Params.from_params(%{unknown => "false", "results" => "country; DROP TABLE votes"})
    assert state == Params.defaults()
    assert Params.to_query(state) == %{}
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    state =
      Params.put(Params.defaults(), %{
        results: :country,
        country_results_filters:
          Map.put(Params.defaults().country_results_filters, unknown, false)
      })

    assert Params.to_query(state) == %{results: "country"}
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end

  test "opinion sort round-trips and defaults to new" do
    assert Params.from_params(%{}).opinion_order == :new
    assert Params.to_query(Params.defaults()) == %{}

    state = Params.from_params(%{"sort" => "top"})

    assert state.opinion_order == :top
    assert Params.to_query(state) == %{sort: "top"}
    assert Params.from_params(Params.to_query(state)) == state
  end
end
