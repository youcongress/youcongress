defmodule YouCongressWeb.EndpointTest do
  use ExUnit.Case, async: true

  test "uses the Bandit web server adapter" do
    endpoint_config = Application.fetch_env!(:you_congress, YouCongressWeb.Endpoint)

    assert endpoint_config[:adapter] == Bandit.PhoenixAdapter
  end
end
