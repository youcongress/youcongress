#!/usr/bin/env elixir

# Pseudoanonymizes the `email` and `phone_number` columns and removes password
# hashes in a PostgreSQL SQL dump's `COPY ... users (...) FROM stdin;` section.
#
# Usage:
#
#   elixir scripts/pseudoanonymize_users_dump.exs @../20260802.sql > ../20260802.pseudoanonymized.sql
#   elixir scripts/pseudoanonymize_users_dump.exs @../20260802.sql --output ../20260802.pseudoanonymized.sql
#
# The @ prefix is accepted for convenience. Output is deliberately written to
# stdout by default, so the source dump is never modified in place.

defmodule PseudoanonymizeUsersDump do
  @kept_email "hecpeare@gmail.com"

  def main(argv) do
    case parse_args(argv) do
      {:ok, input_path, output_path} ->
        input_path
        |> File.stream!(:line, [])
        |> transform()
        |> write(output_path)

      {:error, message} ->
        IO.warn(message <> "\n\n" <> usage())
        System.halt(1)
    end
  end

  defp parse_args([input]), do: {:ok, normalize_input_path(input), :stdio}

  defp parse_args([input, "--output", output]),
    do: {:ok, normalize_input_path(input), {:file, output}}

  defp parse_args(["--output", output, input]),
    do: {:ok, normalize_input_path(input), {:file, output}}

  defp parse_args(_), do: {:error, "Expected one input dump path."}

  defp normalize_input_path("@" <> path), do: path
  defp normalize_input_path(path), do: path

  defp usage do
    "Usage: elixir scripts/pseudoanonymize_users_dump.exs @PATH [--output PATH]"
  end

  defp transform(lines), do: Stream.transform(lines, :outside, &transform_line/2)

  defp transform_line(line, :outside) do
    case users_copy_columns(line) do
      {:ok, columns} -> {[line], {:users_copy, columns}}
      :error -> {[line], :outside}
    end
  end

  defp transform_line("\\.\n" = line, {:users_copy, _columns}), do: {[line], :outside}
  defp transform_line("\\.\r\n" = line, {:users_copy, _columns}), do: {[line], :outside}

  defp transform_line(line, {:users_copy, columns}) do
    {[pseudoanonymize_row(line, columns)], {:users_copy, columns}}
  end

  # Matches both COPY users (...) and COPY public.users (...) headers.
  defp users_copy_columns(line) do
    case Regex.run(~r/^COPY\s+(?:public\.)?users\s*\((.+)\)\s+FROM\s+stdin;\s*$/i, String.trim(line)) do
      [_, columns] ->
        columns =
          columns
          |> String.split(",")
          |> Enum.map(&(&1 |> String.trim() |> String.trim("\"")))

        if Enum.all?(["id", "email", "hashed_password", "phone_number"], &(&1 in columns)),
          do: {:ok, columns},
          else: :error

      nil ->
        :error
    end
  end

  defp pseudoanonymize_row(line, columns) do
    line_ending = if String.ends_with?(line, "\r\n"), do: "\r\n", else: "\n"
    values = line |> String.trim_trailing("\n") |> String.trim_trailing("\r") |> String.split("\t")

    id = Enum.at(values, column_index(columns, "id"))
    email_index = column_index(columns, "email")
    password_index = column_index(columns, "hashed_password")
    phone_index = column_index(columns, "phone_number")

    values
    |> List.replace_at(email_index, pseudoanonymize_email(Enum.at(values, email_index), id))
    |> List.replace_at(password_index, "\\N")
    |> List.replace_at(phone_index, pseudoanonymize_phone(Enum.at(values, phone_index), id))
    |> Enum.join("\t")
    |> Kernel.<>(line_ending)
  end

  defp column_index(columns, column), do: Enum.find_index(columns, &(&1 == column))

  # Keep the requested administrator account usable. All other generated email
  # addresses use the reserved .invalid TLD and remain unique by user ID.
  defp pseudoanonymize_email(email, id) do
    if String.downcase(email) == @kept_email,
      do: email,
      else: "user-#{id}@example.invalid"
  end

  # Preserve NULLs. For present values create a deterministic, non-routable
  # E.164-shaped number (+999 is an unassigned country code), derived from ID.
  defp pseudoanonymize_phone("\\N", _id), do: "\\N"

  defp pseudoanonymize_phone(_phone, id) do
    suffix =
      id
      |> then(&:crypto.hash(:sha256, "users-phone:" <> &1))
      |> :binary.decode_unsigned()
      |> rem(1_000_000_000_000)
      |> Integer.to_string()
      |> String.pad_leading(12, "0")

    "+999" <> suffix
  end

  defp write(lines, :stdio), do: Enum.each(lines, &IO.write/1)

  defp write(lines, {:file, output_path}) do
    case File.open(output_path, [:write, :binary]) do
      {:ok, device} ->
        try do
          Enum.each(lines, &IO.write(device, &1))
        after
          File.close(device)
        end

      {:error, reason} ->
        IO.warn("Could not write #{output_path}: #{:file.format_error(reason)}")
        System.halt(1)
    end
  end
end

PseudoanonymizeUsersDump.main(System.argv())
