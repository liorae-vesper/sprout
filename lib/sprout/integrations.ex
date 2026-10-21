defmodule Sprout.Integrations do
  @moduledoc """
  Private-beta integration provisioning, field grants, and retry-safe sensor ingestion.

  Credential provisioning is a trusted operator operation. API callers receive
  only explicitly granted fields and capabilities. Keys expire after 90 days;
  only SHA-256 digests and non-secret prefixes are retained. Clients must protect
  their bearer key. Revocation blocks subsequent authenticated requests.
  """
  import Ecto.Query
  alias Ecto.Adapters.SQL
  alias Ecto.Changeset
  alias Sprout.{Events, Monitoring, Repo}
  alias Sprout.Integrations.{Client, Request}
  alias Sprout.Land.Plot
  alias Sprout.Monitoring.{Reading, Sample}

  @doc "Lists credential metadata and field grants; it cannot recover raw keys."
  @spec list_clients() :: [Client.t()]
  def list_clients, do: Repo.all(from c in Client, order_by: [desc: c.id], preload: [:fields])

  @doc "Issues a 90-day field-scoped key, returning the raw secret exactly once to the caller."
  @spec create_client(map()) :: {:ok, Client.t(), String.t()} | {:error, Changeset.t()}
  def create_client(attrs) do
    token = "sprout_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    client = %Client{
      token_digest: digest(token),
      token_prefix: String.slice(token, 0, 15),
      expires_at: DateTime.add(now(), 90, :day)
    }

    changeset = client |> Client.changeset(attrs) |> attach_fields()

    case Repo.insert(changeset) do
      {:ok, client} -> {:ok, client, token}
      error -> error
    end
  end

  defp attach_fields(%{valid?: false} = changeset), do: changeset

  defp attach_fields(changeset) do
    ids = Changeset.get_field(changeset, :field_ids)
    fields = Repo.all(from f in Plot, where: f.id in ^ids)

    if length(fields) == length(ids),
      do: Changeset.put_assoc(changeset, :fields, fields),
      else: Changeset.add_error(changeset, :field_ids, "contains an unknown field")
  end

  @doc "Authenticates an unexpired, unrevoked bearer secret without storing or logging it."
  @spec authenticate(term()) :: {:ok, Client.t()} | {:error, :unauthorized}
  def authenticate(token) when is_binary(token) and byte_size(token) <= 128 do
    hash = digest(token)

    case Repo.one(
           from c in Client,
             where: c.token_digest == ^hash and is_nil(c.revoked_at) and c.expires_at > ^now()
         ) do
      nil -> {:error, :unauthorized}
      client -> {:ok, client}
    end
  end

  def authenticate(_), do: {:error, :unauthorized}

  @doc "Revokes a credential while retaining its grants and request history."
  @spec revoke_client(integer()) :: {:ok, Client.t()} | {:error, :not_found | Changeset.t()}
  def revoke_client(id) do
    case Repo.get(Client, id) do
      nil -> {:error, :not_found}
      client -> client |> Changeset.change(revoked_at: now()) |> Repo.update()
    end
  end

  @doc "Returns field grants for an authenticated client, ordered by ID. Check scopes separately."
  @spec permitted_fields(Client.t()) :: [Plot.t()]
  def permitted_fields(client) do
    client |> Ecto.assoc(:fields) |> order_by([f], f.id) |> Repo.all()
  end

  @doc "Checks a capability on an authenticated client."
  @spec has_scope?(Client.t(), String.t()) :: boolean()
  def has_scope?(client, scope), do: scope in client.scopes

  @doc "Resolves a granted field; unauthorized and nonexistent field IDs both return not_found."
  @spec authorized_field(Client.t(), term(), String.t()) :: {:ok, Plot.t()} | {:error, atom()}
  def authorized_field(client, id, scope) do
    with true <- has_scope?(client, scope),
         {:ok, id} <- field_id(id) do
      case Repo.one(from f in Ecto.assoc(client, :fields), where: f.id == ^id) do
        nil -> {:error, :not_found}
        field -> {:ok, field}
      end
    else
      false -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  defp field_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807,
    do: {:ok, id}

  defp field_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> field_id(parsed)
      _ -> {:error, :not_found}
    end
  end

  defp field_id(_), do: {:error, :not_found}

  @doc """
  Ingests a strict numeric sample once per client/idempotency key.

  The key is 8–128 ASCII letters, digits, dots, colons, underscores, or hyphens.
  Same-key/same-sample retries return the original reading; a changed payload
  or field returns conflict. A transaction and advisory lock serialize concurrent
  retries. Live invalidation is emitted only after a new transaction commits.
  """
  @spec ingest(Client.t(), term(), map(), term()) ::
          {:ok, Reading.t(), :created | :replayed} | {:error, term()}
  def ingest(client, field_id, attrs, key) do
    with {:ok, field} <- authorized_field(client, field_id, "readings:write"),
         :ok <- valid_key(key),
         {:ok, sample} <- sample(attrs) do
      save_once(client, field, sample, key)
    end
  end

  defp valid_key(key) when is_binary(key) do
    if Regex.match?(~r/\A[A-Za-z0-9._:-]{8,128}\z/, key),
      do: :ok,
      else: {:error, :invalid_idempotency_key}
  end

  defp valid_key(_), do: {:error, :invalid_idempotency_key}

  defp sample(attrs) when is_map(attrs) do
    keys = ["moisture", "temperature", "humidity", "water_l"]

    if Enum.sort(Map.keys(attrs)) == Enum.sort(keys) and Enum.all?(keys, &is_number(attrs[&1])) do
      {:ok,
       %Sample{
         moisture: attrs["moisture"],
         temperature: attrs["temperature"],
         humidity: attrs["humidity"],
         water_l: attrs["water_l"]
       }}
    else
      {:error, :invalid_sample}
    end
  end

  defp sample(_), do: {:error, :invalid_sample}

  defp save_once(client, field, sample, key) do
    payload =
      digest(
        :erlang.term_to_binary(
          {field.id, sample.moisture / 1, sample.temperature / 1, sample.humidity / 1,
           sample.water_l / 1}
        )
      )

    result =
      Repo.transaction(fn ->
        SQL.query!(Repo, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
          "integration:#{client.id}:#{key}"
        ])

        case Repo.get_by(Request, client_id: client.id, key: key) do
          nil -> insert_sample(client, field, sample, key, payload)
          request -> replay(request, payload)
        end
      end)

    committed(result)
  end

  defp insert_sample(client, field, sample, key, payload) do
    case Monitoring.ingest_sample(field, sample) do
      {:ok, reading} ->
        Repo.insert!(%Request{
          client_id: client.id,
          key: key,
          payload_digest: payload,
          reading_id: reading.id
        })

        {reading, :created}

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp replay(%Request{payload_digest: payload} = request, payload),
    do: {Repo.get!(Reading, request.reading_id), :replayed}

  defp replay(_, _), do: Repo.rollback(:conflict)

  defp committed({:ok, {reading, :created}}) do
    Events.saved({:ok, reading}, :reading)
    {:ok, reading, :created}
  end

  defp committed({:ok, {reading, :replayed}}), do: {:ok, reading, :replayed}
  defp committed({:error, reason}), do: {:error, reason}
  defp digest(value), do: :crypto.hash(:sha256, value)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
