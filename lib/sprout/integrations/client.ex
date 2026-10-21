defmodule Sprout.Integrations.Client do
  @moduledoc "Field-scoped integration credential metadata. Raw secrets are never persisted."
  use Ecto.Schema
  import Ecto.Changeset
  @type t :: %__MODULE__{}
  @scopes ["fields:read", "readings:read", "readings:write"]

  schema "integration_clients" do
    field :name, :string
    field :scopes, {:array, :string}
    field :field_ids, {:array, :integer}, virtual: true
    field :token_digest, :binary, redact: true
    field :token_prefix, :string
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    many_to_many :fields, Sprout.Land.Plot,
      join_through: "integration_fields",
      join_keys: [client_id: :id, field_id: :id]

    timestamps(type: :utc_datetime)
  end

  @doc "Returns the supported capability names for provisioning forms."
  @spec scopes() :: [String.t()]
  def scopes, do: @scopes

  @doc "Validates an operator's requested name, capabilities, and field grants."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(client, attrs) do
    client
    |> cast(attrs, [:name, :scopes, :field_ids])
    |> validate_required([:name, :scopes, :field_ids])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_length(:scopes, min: 1, max: 3)
    |> validate_subset(:scopes, @scopes)
    |> validate_length(:field_ids, min: 1, max: 100)
    |> update_change(:field_ids, &Enum.uniq/1)
    |> validate_change(:field_ids, fn :field_ids, ids ->
      if Enum.all?(ids, &(&1 > 0 and &1 <= 9_223_372_036_854_775_807)),
        do: [],
        else: [field_ids: "must contain valid field IDs"]
    end)
    |> unique_constraint(:token_digest)
  end
end
