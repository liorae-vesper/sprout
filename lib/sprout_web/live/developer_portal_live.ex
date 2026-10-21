defmodule SproutWeb.DeveloperPortalLive do
  @moduledoc """
  Trusted private-beta operator portal for provisioning scoped integration keys.

  The environment gate is checked on mount and every event. This is not a public
  signup console: any browser admitted to it can issue/revoke credentials for
  this single-farm demo. Secrets live only in the current socket until dismissed;
  the repository retains only a digest and prefix.
  """
  use SproutWeb, :live_view
  alias Sprout.{Integrations, Land}
  alias Sprout.Integrations.Client
  alias SproutWeb.DeveloperPortalAccess

  @impl true
  def mount(_params, _session, socket) do
    if DeveloperPortalAccess.enabled?() do
      {:ok,
       socket
       |> assign(
         page_title: "Sprout for builders",
         new_secret: nil,
         notice: nil,
         api_base: SproutWeb.Endpoint.url()
       )
       |> refresh()}
    else
      {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    if DeveloperPortalAccess.enabled?(),
      do: dispatch(event, params, socket),
      else: {:noreply, socket |> assign(new_secret: nil) |> push_navigate(to: ~p"/")}
  end

  defp dispatch("create-client", %{"client" => attrs}, socket) do
    socket = assign(socket, new_secret: nil)

    case Integrations.create_client(attrs) do
      {:ok, _client, secret} ->
        {:noreply,
         socket
         |> assign(new_secret: secret, notice: "Your integration is ready to grow.")
         |> refresh()}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(%{changeset | action: :insert}, as: :client),
           notice: "Could not issue a key. Check the name, scopes, and field grants."
         )}
    end
  end

  defp dispatch("dismiss-key", _, socket), do: {:noreply, assign(socket, new_secret: nil)}

  defp dispatch("revoke-client", %{"id" => id}, socket) do
    case Enum.find(Integrations.list_clients(), &(to_string(&1.id) == id)) do
      nil ->
        {:noreply, assign(socket, notice: "Integration not found.")}

      client ->
        {:ok, _} = Integrations.revoke_client(client.id)

        {:noreply,
         socket
         |> assign(notice: "Key revoked. Future API requests will be rejected.", new_secret: nil)
         |> refresh()}
    end
  end

  defp refresh(socket) do
    fields = Land.list_fields()
    clients = Integrations.list_clients()
    defaults = %{scopes: ["fields:read"], field_ids: Enum.take(Enum.map(fields, & &1.id), 1)}

    socket
    |> assign(
      form: to_form(Client.changeset(%Client{}, defaults), as: :client),
      field_options: Enum.map(fields, &{&1.name, &1.id}),
      has_fields: fields != [],
      client_count: length(clients)
    )
    |> stream(:clients, clients, reset: true)
  end

  defp status(%{revoked_at: date}) when not is_nil(date), do: "Revoked"

  defp status(client),
    do:
      if(DateTime.compare(client.expires_at, DateTime.utc_now()) == :gt,
        do: "Active",
        else: "Expired"
      )

  defp list_example(base),
    do:
      "curl --fail-with-body #{base}/api/v1/fields \\\n  -H \"Authorization: Bearer $SPROUT_API_KEY\""

  defp write_example(base),
    do:
      "curl --fail-with-body -X POST #{base}/api/v1/fields/$FIELD_ID/readings \\\n  -H \"Authorization: Bearer $SPROUT_API_KEY\" \\\n  -H \"Content-Type: application/json\" \\\n  -H \"Idempotency-Key: leaf-sample-0001\" \\\n  -d '{\"moisture\":44,\"temperature\":25,\"humidity\":68,\"water_l\":2}'"
end
