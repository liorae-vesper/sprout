defmodule Sprout.Monitoring.Sample do
  @moduledoc """
  Transport-independent device sample in the farm's canonical units.

  Adapters decode vendor payloads into percentages (`moisture`, `humidity`),
  Celsius (`temperature`), and liters consumed during the sampling interval
  (`water_l`, not a cumulative meter total). All four values are required.
  `Sprout.Monitoring.ingest_sample/3` applies range validation and assigns the
  field and source; samples cannot override ownership or persisted timestamps.
  """
  @enforce_keys [:moisture, :temperature, :humidity, :water_l]
  defstruct [:moisture, :temperature, :humidity, :water_l]

  @type t :: %__MODULE__{
          moisture: number(),
          temperature: number(),
          humidity: number(),
          water_l: number()
        }
end
