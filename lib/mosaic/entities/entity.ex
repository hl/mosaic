defmodule Mosaic.Entities.Entity do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mosaic.Participations.Participation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "entities" do
    field :entity_type, :string
    field :properties, :map, default: %{}

    has_many :participations, Participation, foreign_key: :participant_id

    timestamps(type: :utc_datetime)
  end

  @entity_types ~w(person organization location resource)

  @doc false
  def changeset(entity, attrs) do
    entity
    |> cast(attrs, [:entity_type, :properties])
    |> validate_required([:entity_type])
    |> validate_inclusion(:entity_type, @entity_types)
  end

  @doc """
  Changeset specifically for creating a worker (person entity).
  """
  def worker_changeset(entity, attrs) do
    entity
    |> cast(attrs, [:properties])
    |> put_change(:entity_type, "person")
    |> validate_required([:entity_type])
    |> validate_worker_properties()
  end

  defp validate_worker_properties(changeset) do
    case get_field(changeset, :properties) do
      %{} = props ->
        errors = []

        errors =
          if is_nil(props["name"]) or props["name"] == "",
            do: [{:properties, "name is required"}] ++ errors,
            else: errors

        errors =
          if is_nil(props["email"]) or props["email"] == "",
            do: [{:properties, "email is required"}] ++ errors,
            else: errors

        errors =
          if props["email"] && !String.match?(props["email"], ~r/@/),
            do: [{:properties, "email must be valid"}] ++ errors,
            else: errors

        Enum.reduce(errors, changeset, fn {key, msg}, acc ->
          add_error(acc, key, msg)
        end)

      _ ->
        add_error(changeset, :properties, "must be a map")
    end
  end
end
