defmodule SproutWeb.DashboardLive do
  @moduledoc """
  Single-farm dashboard that delegates writes to domain contexts.

  PubSub invalidations rebuild the read model and reset display streams. The
  recent sensor plot is bounded to 24 samples. Originals enter the private
  imaging pipeline through LiveView’s size-limited upload mechanism.
  """
  use SproutWeb, :live_view
  alias Ecto.Changeset
  alias Sprout.{Cultivation, Equipment, Health, Imaging, Land, Monitoring}
  alias Sprout.Cultivation.Crop
  alias Sprout.Equipment.Asset
  alias Sprout.Health.Finding
  alias SproutWeb.LandIntake

  def mount(_, _, socket) do
    if connected?(socket), do: Monitoring.subscribe()
    fields = Land.list_fields()

    {:ok,
     socket
     |> assign(
       page_title: "Sprout · A little closer to your farm",
       tab: "overview",
       selected_id: if(fields == [], do: nil, else: hd(fields).id),
       notice: nil
     )
     |> allow_upload(:leaf, accept: ~w(.jpg .jpeg .png), max_entries: 1, max_file_size: 8_000_000)
     |> refresh()}
  end

  defp forms(socket, selected) do
    blank =
      Changeset.cast(
        {%{}, %{name: :string, area_ha: :float, boundary: :string, parcel_id: :integer}},
        %{},
        [
          :name,
          :area_ha,
          :boundary,
          :parcel_id
        ]
      )

    finding =
      Finding.changeset(%Finding{}, %{
        kind: :pest,
        severity: 0.1,
        latitude: if(selected, do: center(selected, 0)),
        longitude: if(selected, do: center(selected, 1))
      })

    socket
    |> assign(:field_form, to_form(blank, as: :field))
    |> assign(:parcel_form, to_form(blank, as: :parcel))
    |> assign(
      :crop_form,
      to_form(Crop.changeset(%Crop{}, %{}), as: :crop)
    )
    |> assign(:finding_form, to_form(finding, as: :finding))
    |> assign(
      :asset_form,
      to_form(
        Asset.changeset(%Asset{}, %{kind: :pump, status: :ready}),
        as: :asset
      )
    )
    |> assign(:photo_form, to_form(%{}, as: :photo))
  end

  defp refresh(socket) do
    fields = Land.list_plots()
    parcels = Land.list_parcels()
    selected = Enum.find(fields, &(&1.id == socket.assigns.selected_id)) || List.first(fields)

    cards = Enum.map(fields, &field_card/1)

    current = Enum.find(cards, &(&1.field.id == (selected && selected.id)))
    assets = Equipment.list_assets()
    photos = if(selected, do: Imaging.list_photos(selected.id), else: [])

    socket
    |> assign(summary(fields, cards))
    |> assign(
      parcel_count: length(parcels),
      parcel_options: Enum.map(parcels, &{&1.name, &1.id}),
      map_parcels: Enum.map(parcels, &Map.take(&1, [:id, :name, :area_ha, :boundary])),
      land_area: Enum.reduce(parcels, 0, &(&1.area_ha + &2)),
      next_cycle: selected_cycle(selected),
      map_fields: Enum.map(fields, &Map.take(&1, [:id, :name, :area_ha, :boundary])),
      asset_count: length(assets),
      photos_empty: photos == [],
      findings_empty: is_nil(current) or current.findings == [],
      selected: selected,
      selected_id: selected && selected.id,
      current: current && Map.delete(current, :findings),
      history: selected_history(selected)
    )
    |> forms(selected)
    |> stream(:cycles, if(selected, do: Cultivation.history(selected.id), else: []), reset: true)
    |> stream(:parcels, parcels, reset: true)
    |> stream(
      :field_cards,
      Enum.with_index(cards)
      |> Enum.map(fn {c, i} ->
        Map.merge(Map.delete(c, :findings), %{id: c.field.id, index: i})
      end),
      reset: true
    )
    |> stream(:equipment, assets, reset: true)
    |> stream(:photos, photos, reset: true)
    |> stream(:findings, if(selected, do: Health.list_findings(selected.id), else: []),
      reset: true
    )
  end

  defp selected_history(nil), do: []
  defp selected_history(plot), do: Monitoring.history(plot.id)

  defp selected_cycle(nil), do: nil
  defp selected_cycle(plot), do: Cultivation.next_cycle(plot.id)

  defp field_card(field) do
    crop = Cultivation.active(field.id)
    reading = Monitoring.latest(field.id)
    findings = Health.list_findings(field.id)

    %{
      field: field,
      crop: crop,
      reading: reading,
      findings: findings,
      estimate: if(crop, do: Cultivation.estimate(crop, field.area_ha, reading, findings))
    }
  end

  defp summary(fields, cards) do
    [
      field_count: length(fields),
      active_crop_count: Enum.count(cards, &(&1.crop != nil)),
      total_area: Enum.reduce(fields, 0, &(&1.area_ha + &2)),
      total_yield:
        Enum.reduce(cards, 0, fn card, total -> total + estimated_kg(card.estimate) end),
      open_findings:
        Enum.reduce(cards, 0, fn card, total ->
          total + Enum.count(card.findings, &(&1.status == :open))
        end)
    ]
  end

  defp estimated_kg(nil), do: 0
  defp estimated_kg(%{kg: nil}), do: 0
  defp estimated_kg(%{kg: kg}), do: kg

  def handle_info({:farm_changed, _}, socket), do: {:noreply, refresh(socket)}

  def handle_event("select", %{"id" => id}, socket),
    do: {:noreply, socket |> assign(selected_id: String.to_integer(id), notice: nil) |> refresh()}

  def handle_event("tab", %{"tab" => tab}, socket)
      when tab in ["overview", "equipment", "photos"],
      do: {:noreply, socket |> assign(tab: tab, notice: nil) |> refresh()}

  def handle_event(event, params, socket) when event in ["field-create", "parcel-create"] do
    {kind, attrs} =
      if event == "field-create", do: {:plot, params["field"]}, else: {:parcel, params["parcel"]}

    case LandIntake.create(kind, attrs) do
      {:ok, record} ->
        socket = if kind == :plot, do: assign(socket, :selected_id, record.id), else: socket

        {:noreply,
         socket
         |> assign(notice: "New #{kind} saved. A little more room to grow.")
         |> refresh()
         |> push_event("land-saved", %{kind: kind})}

      {:error, error} ->
        {:noreply, assign(socket, notice: LandIntake.message(error))}
    end
  end

  def handle_event("plot-state", %{"status" => status}, socket) do
    target = Enum.find([:resting, :preparing, :ready], &(to_string(&1) == status))

    result(
      socket,
      Cultivation.transition_plot(socket.assigns.selected, target),
      "Soil status updated."
    )
  end

  def handle_event("cycle", %{"target" => target}, socket) do
    cycle = socket.assigns.next_cycle
    target = Enum.find([:growing, :cancelled], &(to_string(&1) == target))
    result(socket, next_transition(cycle, target), "Crop cycle updated.")
  end

  def handle_event("crop-create", %{"crop" => attrs}, socket),
    do:
      result(
        socket,
        Cultivation.plan_crop(socket.assigns.selected, attrs),
        "Next crop planned. Prepare the plot before planting."
      )

  def handle_event("asset-create", %{"asset" => attrs}, socket),
    do:
      result(
        socket,
        Equipment.create_asset(socket.assigns.selected, attrs),
        "A new helping hand for your field."
      )

  def handle_event("finding", %{"finding" => attrs}, socket),
    do:
      result(
        socket,
        Health.record_finding(socket.assigns.selected, attrs),
        "Field note saved. Your estimate has been refreshed."
      )

  def handle_event("resolve", %{"id" => id}, socket) do
    finding =
      Enum.find(Health.list_findings(socket.assigns.selected_id), &(to_string(&1.id) == id))

    if finding,
      do:
        result(socket, Health.resolve(finding.id), "Finding resolved. Keep an eye on this patch!"),
      else: {:noreply, socket}
  end

  def handle_event("asset", %{"id" => id}, socket) do
    asset = Enum.find(Equipment.list_assets(), &(to_string(&1.id) == id))

    if asset,
      do:
        result(
          socket,
          Equipment.set_status(
            asset.id,
            if(asset.status == :ready, do: :maintenance, else: :ready)
          ),
          "Equipment status updated."
        ),
      else: {:noreply, socket}
  end

  def handle_event("crop", _, socket) do
    case socket.assigns.current.crop do
      nil ->
        {:noreply, socket}

      crop ->
        result(
          socket,
          Cultivation.transition(
            crop,
            if(crop.status == :planned, do: :growing, else: :harvested)
          ),
          "Crop cycle updated."
        )
    end
  end

  def handle_event("validate-photo", _, socket), do: {:noreply, socket}

  def handle_event("upload", _, socket) do
    results =
      consume_uploaded_entries(socket, :leaf, fn %{path: path}, entry ->
        {:ok, Imaging.ingest(socket.assigns.selected, path, entry.client_name)}
      end)

    if results != [] and Enum.all?(results, &match?({:ok, _}, &1)),
      do:
        {:noreply,
         socket
         |> assign(notice: "Photo preserved. Awaiting a future inference model.")
         |> refresh()},
      else: {:noreply, assign(socket, notice: "Please choose a valid PNG or JPEG under 8 MB.")}
  end

  defp next_transition(nil, _), do: {:error, :invalid_transition}
  defp next_transition(cycle, target), do: Cultivation.transition(cycle, target)

  defp result(socket, {:ok, _}, message),
    do: {:noreply, socket |> assign(notice: message) |> refresh()}

  defp result(socket, {:error, error}, _),
    do: {:noreply, assign(socket, notice: LandIntake.message(error))}

  defp center(field, coordinate),
    do:
      Enum.map(field.boundary["points"], &Enum.at(&1, coordinate))
      |> then(&(Enum.sum(&1) / length(&1)))

  defp crop_icon(index), do: Enum.at(["🍓", "🌽", "🥬", "🍅"], rem(index, 4))
  defp number(nil), do: "—"
  defp number(n), do: :erlang.float_to_binary(n / 1, decimals: 1)

  defp sparkline(history) do
    history
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {r, i} ->
      "#{10 + i * 270 / max(length(history) - 1, 1)},#{90 - r.moisture * 0.7}"
    end)
  end

  defp source_label(:simulated), do: "Receiving simulated data"
  defp source_label(:device), do: "Latest device reading"
  defp source_label(:manual), do: "Latest manual reading"

  defp freshness(nil), do: "No readings"

  defp freshness(r),
    do:
      if(DateTime.diff(DateTime.utc_now(), r.inserted_at) > 120,
        do: "Stale reading",
        else: source_label(r.source)
      )
end
