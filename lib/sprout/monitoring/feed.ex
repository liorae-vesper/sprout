defmodule Sprout.Monitoring.Feed do
  @moduledoc """
  Adapter-configured polling worker with bounded per-field tasks.

  Configure `:adapter` and optional `:adapter_options`, `:interval` (5000 ms),
  `:timeout` (2000 ms), and `:max_concurrency` (4). A completed batch schedules
  the next interval, so batches do not overlap. Failed reads are logged and
  retried next interval; successful fields remain independent. No fake fallback
  is used when a real device fails.

  Tasks run under `Sprout.Monitoring.Tasks`; callers testing this worker must
  share database sandbox access with its worker tasks.
  """
  use GenServer
  require Logger
  alias Sprout.{Land, Monitoring}

  @doc "Starts an unregistered polling worker. Invalid options return `:invalid_config`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    settings =
      Map.new(
        Keyword.merge(
          [interval: 5000, timeout: 2000, max_concurrency: 4, adapter_options: []],
          opts
        )
      )

    if valid_settings?(settings),
      do: GenServer.start_link(__MODULE__, settings),
      else: {:error, :invalid_config}
  end

  @impl true
  def init(settings) do
    schedule(settings)
    {:ok, settings}
  end

  @impl true
  def handle_info(:poll, settings) do
    poll(settings)
    schedule(settings)
    {:noreply, settings}
  end

  defp valid_settings?(%{adapter: adapter} = settings) when is_atom(adapter) do
    Code.ensure_loaded?(adapter) and function_exported?(adapter, :source, 0) and
      function_exported?(adapter, :read, 3) and positive_limits?(settings) and
      Keyword.keyword?(settings.adapter_options)
  end

  defp valid_settings?(_), do: false

  defp positive_limits?(settings) do
    Enum.all?(
      [settings.interval, settings.timeout, settings.max_concurrency],
      &(is_integer(&1) and &1 > 0)
    )
  end

  defp schedule(settings), do: Process.send_after(self(), :poll, settings.interval)

  defp poll(settings) do
    fields = Land.list_fields()

    results =
      Task.Supervisor.async_stream_nolink(
        Monitoring.Tasks,
        fields,
        fn field -> Monitoring.poll_field(field, settings.adapter, settings.adapter_options) end,
        timeout: settings.timeout,
        on_timeout: :kill_task,
        max_concurrency: settings.max_concurrency
      )

    fields |> Enum.zip(results) |> Enum.each(&report/1)
  rescue
    exception -> Logger.warning("Sensor polling unavailable: #{Exception.message(exception)}")
  end

  defp report({_field, {:ok, {:ok, _reading}}}), do: :ok

  defp report({field, _error}),
    do: Logger.warning("Sensor poll failed for field #{field.id}; retrying next interval")
end
