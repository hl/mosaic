defmodule Mosaic.Participations do
  @moduledoc """
  The Participations context for managing entity participation in events.
  """

  import Ecto.Query, warn: false
  alias Mosaic.Repo
  alias Mosaic.Participations.Participation

  @doc """
  Adds a participation linking an entity to an event.
  """
  def add_participation(participant_id, event_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put("participant_id", participant_id)
      |> Map.put("event_id", event_id)

    %Participation{}
    |> Participation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Removes a participation.
  """
  def remove_participation(%Participation{} = participation) do
    Repo.delete(participation)
  end

  @doc """
  Gets a single participation.
  """
  def get_participation!(id) do
    Repo.get!(Participation, id)
  end

  @doc """
  Lists participations for a given event.
  """
  def list_participations_for_event(event_id) do
    Participation
    |> where([p], p.event_id == ^event_id)
    |> Repo.all()
    |> Repo.preload([:participant, :event])
  end

  @doc """
  Lists participations for a given entity.
  """
  def list_participations_for_entity(entity_id) do
    Participation
    |> where([p], p.participant_id == ^entity_id)
    |> Repo.all()
    |> Repo.preload([:participant, :event])
  end
end
