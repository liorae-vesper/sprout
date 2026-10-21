defmodule Sprout.TestDeviceAdapter do
  @moduledoc false
  @behaviour Sprout.Monitoring.DeviceAdapter
  alias Sprout.Monitoring.Sample

  @impl true
  def source, do: :device

  @impl true
  def read(field, previous, opts) do
    send(Keyword.fetch!(opts, :test_pid), {:device_read, field.id, previous && previous.id})

    mode =
      if field.id == opts[:fail_field_id],
        do: Keyword.get(opts, :failure_mode, :error),
        else: Keyword.get(opts, :mode, :good)

    if mode == :controlled do
      send(Keyword.fetch!(opts, :test_pid), {:device_request, field.id, self()})

      receive do
        {:reply, response} -> respond(response)
      end
    else
      respond(mode)
    end
  end

  defp respond(:good),
    do: {:ok, struct!(Sample, moisture: 52.5, temperature: 23.1, humidity: 61.2, water_l: 4.5)}

  defp respond(:error), do: {:error, :unreachable}

  defp respond(:invalid),
    do: {:ok, struct!(Sample, moisture: 120, temperature: 23, humidity: 60, water_l: 1)}

  defp respond(:malformed), do: {:ok, %{moisture: 50}}
  defp respond(:raise), do: raise("transport failed")
  defp respond(:exit), do: exit(:connection_lost)

  defp respond(:block) do
    receive do
      :release -> respond(:good)
    end
  end
end
