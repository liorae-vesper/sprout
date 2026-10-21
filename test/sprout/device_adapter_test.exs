defmodule Sprout.Monitoring.DeviceAdapterTest do
  use Sprout.DataCase
  alias Sprout.{Demo, Land, Monitoring, TestDeviceAdapter}
  alias Sprout.Monitoring.{Sample, SimulatedAdapter}

  setup do
    Demo.seed!()
    %{field: hd(Land.list_fields())}
  end

  test "a configured adapter feeds normalized readings through persistence and PubSub", %{
    field: field
  } do
    previous = Monitoring.latest(field.id)
    Monitoring.subscribe()
    assert {:ok, reading} = Monitoring.poll_field(field, TestDeviceAdapter, test_pid: self())
    assert_receive {:device_read, id, previous_id}
    assert {id, previous_id} == {field.id, previous.id}
    assert reading.source == :device
    assert reading.moisture == 52.5
    assert Monitoring.latest(field.id).id == reading.id
    assert_receive {:farm_changed, :reading}
  end

  test "adapter errors, malformed responses and invalid values never save or broadcast", %{
    field: field
  } do
    previous = Monitoring.latest(field.id)
    Monitoring.subscribe()

    assert {:error, {:adapter, :unreachable}} =
             Monitoring.poll_field(field, TestDeviceAdapter, test_pid: self(), mode: :error)

    assert {:error, :invalid_adapter_response} =
             Monitoring.poll_field(field, TestDeviceAdapter, test_pid: self(), mode: :malformed)

    assert {:error, %Ecto.Changeset{}} =
             Monitoring.poll_field(field, TestDeviceAdapter, test_pid: self(), mode: :invalid)

    assert Monitoring.latest(field.id).id == previous.id
    refute_receive {:farm_changed, :reading}
  end

  test "push delivery shares ingestion, defaults to real devices and validates samples", %{
    field: field
  } do
    sample = struct!(Sample, moisture: 44, temperature: 25, humidity: 68, water_l: 0)
    assert {:ok, reading} = Monitoring.ingest_sample(field, sample)
    assert reading.source == :device
    assert reading.water_l == 0
    assert {:error, %Ecto.Changeset{}} = Monitoring.ingest_sample(field, %{sample | moisture: -1})
    assert {:error, :invalid_source} = Monitoring.ingest_sample(field, sample, :manual)
  end

  test "simulation implements the same contract, including fields without history", %{
    field: field
  } do
    assert :simulated == SimulatedAdapter.source()

    for previous <- [nil, %{moisture: 5}, %{moisture: 95}] do
      assert {:ok, sample} = SimulatedAdapter.read(field, previous, [])
      assert sample.moisture >= 5 and sample.moisture <= 95
    end

    assert {:ok, %{source: :simulated}} = Monitoring.poll_field(field, SimulatedAdapter)
  end
end
