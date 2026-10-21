defmodule SproutWeb.IntegrationAPIController do
  @moduledoc "Versioned private-beta JSON API. Authorization and ingestion stay in domain contexts."
  use SproutWeb, :controller
  alias Ecto.Changeset
  alias Sprout.{Integrations, Monitoring}

  @doc "Returns only fields explicitly granted to a key with fields:read permission."
  @spec fields(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def fields(conn, _) do
    client = conn.assigns.integration_client

    if Integrations.has_scope?(client, "fields:read") do
      json(conn, %{data: Enum.map(Integrations.permitted_fields(client), &field_json/1)})
    else
      error(conn, :forbidden)
    end
  end

  @doc "Returns up to 24 readings, ordered oldest first, for one permitted field."
  @spec readings(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def readings(conn, %{"field_id" => id}) do
    case Integrations.authorized_field(conn.assigns.integration_client, id, "readings:read") do
      {:ok, field} ->
        json(conn, %{
          data: Enum.map(Monitoring.history(field.id), &reading_json/1),
          meta: %{limit: 24, order: "oldest_first"}
        })

      {:error, reason} ->
        error(conn, reason)
    end
  end

  @doc "Accepts a numeric device sample with a client-scoped retry key."
  @spec create_reading(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create_reading(conn, %{"field_id" => id}) do
    key =
      case get_req_header(conn, "idempotency-key") do
        [key] -> key
        _ -> nil
      end

    result = Integrations.ingest(conn.assigns.integration_client, id, conn.body_params, key)

    case result do
      {:ok, reading, mode} ->
        conn
        |> put_resp_header("idempotency-replayed", to_string(mode == :replayed))
        |> put_status(if(mode == :created, do: 201, else: 200))
        |> json(%{data: reading_json(reading)})

      {:error, reason} ->
        error(conn, reason)
    end
  end

  defp field_json(field), do: Map.take(field, [:id, :name, :area_ha, :boundary])

  defp reading_json(reading) do
    reading
    |> Map.take([:id, :field_id, :moisture, :temperature, :humidity, :water_l, :source])
    |> Map.put(:recorded_at, reading.inserted_at)
  end

  defp error(conn, %Changeset{} = changeset) do
    fields =
      Changeset.traverse_errors(changeset, fn {message, options} ->
        Enum.reduce(options, message, fn {key, value}, text ->
          String.replace(text, "%{#{key}}", to_string(value))
        end)
      end)

    conn
    |> put_status(422)
    |> json(%{
      errors: %{code: "invalid_sample", detail: "The sample failed validation.", fields: fields}
    })
  end

  defp error(conn, reason) do
    {status, detail} = error_details(reason)
    conn |> put_status(status) |> json(%{errors: %{code: to_string(reason), detail: detail}})
  end

  defp error_details(:forbidden), do: {403, "This key does not grant the required scope."}
  defp error_details(:not_found), do: {404, "The field is not available to this integration."}

  defp error_details(:conflict),
    do: {409, "This idempotency key was already used for a different sample or field."}

  defp error_details(:invalid_idempotency_key),
    do:
      {400,
       "Provide an Idempotency-Key of 8–128 letters, digits, dots, colons, underscores, or hyphens."}

  defp error_details(:invalid_sample),
    do: {422, "Provide exactly moisture, temperature, humidity, and water_l as JSON numbers."}
end
