defmodule SproutWeb.APIContractController do
  @moduledoc "Serves the machine-readable API contract without exposing credentials."
  use SproutWeb, :controller
  @contract Path.expand("../../../priv/openapi.json", __DIR__)
  @external_resource @contract
  @document @contract |> File.read!() |> Jason.decode!()

  @doc "Returns the OpenAPI 3.1 contract for the versioned partner API."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params), do: json(conn, @document)
end
