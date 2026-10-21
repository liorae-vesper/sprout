defmodule SproutWeb.DeveloperPortalAccess do
  @moduledoc "Environment gate for the trusted private-beta operator console; not user authentication."
  @behaviour Plug
  import Plug.Conn

  @doc "Returns whether this deployment explicitly enables the private console."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:sprout, :developer_portal_enabled, false) == true

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")
    if enabled?(), do: conn, else: conn |> send_resp(404, "Not Found") |> halt()
  end
end
