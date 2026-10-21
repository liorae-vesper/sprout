defmodule Sprout.Monitoring.SimulatedAdapter do
  @moduledoc """
  Fake device adapter with bounded moisture drift and generated climate/water samples.

  Implements the same read contract as physical devices. It has no repository
  or PubSub side effects; the monitoring context owns ingestion.
  """
  @behaviour Sprout.Monitoring.DeviceAdapter
  alias Sprout.Monitoring.Sample

  @impl true
  def source, do: :simulated

  @impl true
  def read(_field, previous, _opts) do
    moisture = if previous, do: previous.moisture, else: 45

    {:ok,
     %Sample{
       moisture: Float.round(min(95.0, max(5.0, moisture + (:rand.uniform() - 0.5) * 3)), 1),
       temperature: Float.round(24 + :math.sin(System.system_time(:second) / 60) * 3, 1),
       humidity: Float.round(60 + :rand.uniform() * 10, 1),
       water_l: Float.round(:rand.uniform() * 18, 1)
     }}
  end
end
