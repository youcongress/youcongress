defmodule Mix.Tasks.Countries.ImportGeonames do
  @moduledoc """
  Imports countries from the GeoNames countryInfo.txt dump.

      mix countries.import_geonames
      mix countries.import_geonames --url https://download.geonames.org/export/dump/countryInfo.txt
  """

  use Mix.Task

  alias YouCongress.Countries.GeoNamesImporter

  @shortdoc "Imports countries from GeoNames"
  @requirements ["app.start"]

  @impl true
  def run(args) do
    {opts, _args, _invalid} =
      OptionParser.parse(args,
        strict: [url: :string, quiet: :boolean]
      )

    url = Keyword.get(opts, :url, GeoNamesImporter.country_info_url())

    case GeoNamesImporter.download_and_import(url: url) do
      {:ok, counts} ->
        unless opts[:quiet] do
          Mix.shell().info(
            "Imported countries from GeoNames: #{counts.inserted} inserted, #{counts.updated} updated."
          )
        end

      {:error, reason} ->
        Mix.raise("Could not import GeoNames countries: #{inspect(reason)}")
    end
  end
end
