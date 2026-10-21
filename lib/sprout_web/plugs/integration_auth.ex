defmodule SproutWeb.IntegrationAuth do
  @moduledoc "Authenticates API bearer keys without accepting secrets in URLs or cookies."
  @behaviour Plug
  import Plug.Conn
  alias Sprout.Integrations

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with [header] <- get_req_header(conn, "authorization"),
         [_, token] <- Regex.run(~r/\ABearer ([^\s]+)\z/i, header),
         {:ok, client} <- Integrations.authenticate(token) do
      assign(conn, :integration_client, client)
    else
      _ ->
        conn
        |> put_resp_header("www-authenticate", "Bearer realm=\"sprout\"")
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{
          errors: %{code: "unauthorized", detail: "A valid, active bearer key is required."}
        })
        |> halt()
    end
  end
end
