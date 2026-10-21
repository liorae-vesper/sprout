defmodule Sprout.Integrations.Request do
  @moduledoc "Persisted retry identity linking an integration's idempotency key to one reading."
  use Ecto.Schema
  @type t :: %__MODULE__{}
  schema "integration_requests" do
    field :client_id, :id
    field :key, :string
    field :payload_digest, :binary
    field :reading_id, :id
    timestamps(type: :utc_datetime)
  end
end
