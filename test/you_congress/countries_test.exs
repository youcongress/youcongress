defmodule YouCongress.CountriesTest do
  use YouCongress.DataCase

  import YouCongress.CountriesFixtures

  alias YouCongress.Countries
  alias YouCongress.Countries.Country
  alias YouCongress.Countries.GeoNamesImporter

  describe "countries" do
    test "get_country_by_name_or_iso/1 matches names, ISO codes, and legacy aliases" do
      country = country_fixture(name: "United States", iso_alpha2: "US", iso_alpha3: "USA")

      assert Countries.get_country_by_name_or_iso("United States").id == country.id
      assert Countries.get_country_by_name_or_iso("us").id == country.id
      assert Countries.get_country_by_name_or_iso("USA").id == country.id
      assert Countries.get_country_by_name_or_iso("United States of America").id == country.id
    end

    test "upsert_country/1 updates existing placeholders by name" do
      placeholder = country_fixture(name: "Canada")

      assert {:ok, %Country{} = country, :updated} =
               Countries.upsert_country(%{
                 name: "Canada",
                 iso_alpha2: "CA",
                 iso_alpha3: "CAN",
                 phone_prefix: "+1"
               })

      assert country.id == placeholder.id
      assert country.iso_alpha2 == "CA"
      assert country.iso_alpha3 == "CAN"
      assert country.phone_prefix == "+1"
    end
  end

  describe "GeoNamesImporter" do
    test "parse_country_info/1 extracts country fields and normalizes phone prefixes" do
      text = """
      #ISO\tISO3\tISO-Numeric\tfips\tCountry\tCapital\tArea\tPopulation\tContinent\ttld\tCurrencyCode\tCurrencyName\tPhone
      #{country_info_line("US", "USA", "United States", "1")}
      #{country_info_line("GB", "GBR", "United Kingdom", "+44")}
      """

      assert [
               %{
                 iso_alpha2: "US",
                 iso_alpha3: "USA",
                 name: "United States",
                 phone_prefix: "+1"
               },
               %{
                 iso_alpha2: "GB",
                 iso_alpha3: "GBR",
                 name: "United Kingdom",
                 phone_prefix: "+44"
               }
             ] = GeoNamesImporter.parse_country_info(text)
    end

    test "import_text/1 inserts and updates countries" do
      country_fixture(name: "United States")

      text = """
      #{country_info_line("US", "USA", "United States", "1")}
      #{country_info_line("ES", "ESP", "Spain", "34")}
      """

      assert {:ok, %{inserted: 1, updated: 1}} = GeoNamesImporter.import_text(text)

      assert Countries.get_country_by_name_or_iso("US").phone_prefix == "+1"
      assert Countries.get_country_by_name_or_iso("ES").name == "Spain"
      assert Countries.get_country_by_name_or_iso("Spain").phone_prefix == "+34"
    end
  end

  defp country_info_line(iso_alpha2, iso_alpha3, name, phone_prefix) do
    [
      iso_alpha2,
      iso_alpha3,
      "",
      "",
      name,
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      phone_prefix
    ]
    |> Enum.join("\t")
  end
end
