defmodule Sprout.Monitoring.DeviceAdapter do
  @moduledoc """
  Contract for replaceable polling transports; adapters never persist readings.

  Implement `read/3` to decode a device response into `Sprout.Monitoring.Sample`.
  The previous persisted reading may be nil. Adapter options can contain field-to-device
  mappings or a client reference. Return an explicit error for transport failures;
  `Sprout.Monitoring.Feed` also isolates crashes and enforces an overall poll timeout.

  Push transports can bypass polling and call `Sprout.Monitoring.ingest_sample/3`
  after authentication and payload normalization. This contract does not supply
  device discovery, authentication, or vendor protocols.
  """
  alias Sprout.Land.Plot
  alias Sprout.Monitoring.{Reading, Sample}

  @doc "Identifies the origin of readings. Physical transports return `:device`."
  @callback source() :: :device | :simulated

  @doc "Reads and normalizes one field's device data without writing to the repository."
  @callback read(Plot.t(), Reading.t() | nil, keyword()) :: {:ok, Sample.t()} | {:error, term()}
end
