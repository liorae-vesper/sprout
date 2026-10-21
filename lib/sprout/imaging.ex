defmodule Sprout.Imaging do
  @moduledoc "Private original-image intake and persisted inference lifecycle. No model is installed."
  import Ecto.Query
  alias Sprout.{Imaging.Photo, Repo}
  @max_bytes 8_000_000
  @doc """
  Lists a field’s original-photo metadata newest first.
  """
  @spec list_photos(integer()) :: [Photo.t()]
  def list_photos(field_id),
    do: Repo.all(from p in Photo, where: p.field_id == ^field_id, order_by: [desc: p.id])

  @doc """
  Resolves a persisted photo’s generated storage key under the configured upload directory.

  Accept only metadata created by `ingest/3`; this is not a user-path sanitization API.
  """
  @spec path(Photo.t()) :: String.t()
  def path(photo), do: Path.join(root(), photo.storage_key)
  defp root, do: Application.get_env(:sprout, :upload_dir, Path.expand("var/photos"))

  @doc """
  Preserves a private JPEG/PNG original and records its checksum in PostgreSQL.

  `source` is a local upload path; `filename` is retained as a basename only.
  Files over 8 MB, missing files, unrecognized signatures, and directory-creation
  failures return `{:error, :invalid_image}`. Writing can return filesystem errors;
  invalid metadata returns a changeset and triggers best-effort file cleanup.

  The check recognizes signatures, not complete image decoding. Photos start
  `:awaiting_model`; no inference runs. The configured directory must be writable
  and must remain within the application workspace for cleanup operations.
  """
  @spec ingest(Sprout.Land.Plot.t(), Path.t(), String.t()) ::
          {:ok, Photo.t()} | {:error, atom() | Ecto.Changeset.t()}
  def ingest(field, source, filename) do
    with {:ok, %{size: size}} when size <= @max_bytes <- File.stat(source),
         {:ok, bytes} <- File.read(source),
         {:ok, extension} <- image_type(bytes),
         :ok <- File.mkdir_p(root()) do
      key = Ecto.UUID.generate() <> extension
      target = Path.join(root(), key)

      persist_original(field, filename, key, target, bytes)
    else
      _ -> {:error, :invalid_image}
    end
  end

  defp persist_original(field, filename, key, target, bytes) do
    with :ok <- File.write(target, bytes, [:exclusive]) do
      result =
        %Photo{field_id: field.id}
        |> Photo.changeset(%{
          filename: Path.basename(filename),
          storage_key: key,
          sha256: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
        })
        |> Repo.insert()

      cleanup_failed_insert(result, target)
      Sprout.Events.saved(result, :photo)
    end
  end

  defp cleanup_failed_insert({:error, _}, target), do: File.rm(target)
  defp cleanup_failed_insert(_, _), do: :ok

  defp image_type(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>), do: {:ok, ".png"}
  defp image_type(<<255, 216, 255, _::binary>>), do: {:ok, ".jpg"}
  defp image_type(_), do: {:error, :invalid_image}

  @doc """
  Atomically advances an original’s inference lifecycle using its persisted current status.

  Allowed edges are awaiting_model → processing → completed/failed, and
  failed → processing. Completion requires a nonempty result map. Invalid
  edges/results return `:invalid_transition`; a lost state claim returns `:stale`.
  This state primitive does not schedule jobs or recover interrupted workers.
  """
  @spec transition(Photo.t(), atom(), map() | nil) ::
          {:ok, Photo.t()} | {:error, :invalid_transition | :stale}
  def transition(photo, target, result \\ nil) do
    allowed =
      {photo.status, target} in [
        {:awaiting_model, :processing},
        {:processing, :completed},
        {:processing, :failed},
        {:failed, :processing}
      ]

    if allowed and (target != :completed or (is_map(result) and map_size(result) > 0)) do
      {count, _} =
        Repo.update_all(from(p in Photo, where: p.id == ^photo.id and p.status == ^photo.status),
          set: [
            status: target,
            result: result,
            updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
          ]
        )

      if count == 1,
        do: Sprout.Events.saved({:ok, Repo.get!(Photo, photo.id)}, :photo),
        else: {:error, :stale}
    else
      {:error, :invalid_transition}
    end
  end
end
