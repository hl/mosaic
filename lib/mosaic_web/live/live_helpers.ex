defmodule MosaicWeb.LiveHelpers do
  @moduledoc """
  Shared helper functions for LiveView components.
  """

  @doc """
  Parses datetime-local input from browser forms.
  Browser sends format: "2025-11-19T14:47"

  ## Examples

      iex> parse_datetime_local("2025-11-19T14:47")
      ~U[2025-11-19 14:47:00Z]

      iex> parse_datetime_local(nil)
      nil
  """
  def parse_datetime_local(nil), do: nil
  def parse_datetime_local(""), do: nil

  def parse_datetime_local(datetime_string) when is_binary(datetime_string) do
    with {:error, _} <- parse_with_seconds(datetime_string <> ":00"),
         {:error, _} <- parse_with_seconds(datetime_string) do
      nil
    end
  end

  def parse_datetime_local(_), do: nil

  defp parse_with_seconds(string) do
    with {:ok, naive} <- NaiveDateTime.from_iso8601(string) do
      {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
    end
  end

  @doc """
  Formats DateTime for datetime-local input in browser forms.

  ## Examples

      iex> format_datetime_local(~U[2025-11-19 14:47:00Z])
      "2025-11-19T14:47:00"

      iex> format_datetime_local(nil)
      nil
  """
  def format_datetime_local(nil), do: nil

  def format_datetime_local(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
  end

  @doc """
  Extracts the primary participant from an event.
  Returns the first participant or nil if none exist.
  """
  def get_primary_participant(%{participations: [%{participant: participant} | _]}),
    do: participant

  def get_primary_participant(_), do: nil

  @doc """
  Formats hours as a string with 2 decimal places.

  ## Examples

      iex> format_hours(8.5)
      "8.50h"

      iex> format_hours(nil)
      "-"
  """
  def format_hours(nil), do: "-"

  def format_hours(hours) when is_number(hours) do
    "#{Float.round(hours, 2)}h"
  end
end
