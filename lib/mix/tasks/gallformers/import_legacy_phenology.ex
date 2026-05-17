defmodule Mix.Tasks.Gallformers.ImportLegacyPhenology do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  One-time migration of phenology observations from the legacy SQLite database
  into the new `phenology_observations` table (see migration
  20260517170909_add_phenology_tables.exs and PR #521).

  The CSV input is produced by
  `claudespace/gf_phenology_integration_20260516/convert_phen_to_csv.py`,
  which reads `gallphenReset.sqlite`, resolves the legacy gall_id/host_id to
  the current gallformers species_id (via the phen DB's species mapping
  table), and derives source_type / inat_id from the URL fields.

  ## Usage

      mix gallformers.import_legacy_phenology PATH_TO_CSV [opts]

  ## Options

      --reset            TRUNCATE phenology_observations + phenology_blacklist
                         before importing. Required if the table is non-empty.
      --dry-run          Validate every row through the changeset but insert
                         nothing.
      --batch-size N     Insert N rows per transaction (default: 500).
      --limit N          Only process the first N CSV rows.
      --progress N       Print a progress line every N rows (default: 1000).

  ## Behavior

    * Each CSV row goes through `Gallformers.Phenology.create_observation/1`,
      so all changeset validations (source_type vocabulary, lat/lon/doy ranges,
      inat_id-matches-source_type, FK existence) run.
    * Empty CSV cells are converted to nil before being passed to the
      changeset (CSV has no native nil representation).
    * Per the proposal, raw_* fields are set equal to the processed fields on
      first import (no upstream history to track).
    * Rows that fail validation are counted and a sample is reported at the
      end. The import does NOT abort on validation errors.
  """
  use Mix.Task

  alias Gallformers.Phenology
  alias Gallformers.Repo

  NimbleCSV.define(__MODULE__.Parser, separator: ",", escape: "\"")

  @shortdoc "Import legacy phenology SQLite data via a converted CSV"

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          reset: :boolean,
          dry_run: :boolean,
          batch_size: :integer,
          limit: :integer,
          progress: :integer
        ]
      )

    csv_path =
      case positional do
        [p] -> p
        _ -> Mix.raise("Usage: mix gallformers.import_legacy_phenology PATH_TO_CSV [opts]")
      end

    unless File.exists?(csv_path), do: Mix.raise("CSV not found: #{csv_path}")

    Mix.Task.run("app.start")

    reset? = Keyword.get(opts, :reset, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    batch_size = Keyword.get(opts, :batch_size, 500)
    progress_every = Keyword.get(opts, :progress, 1000)
    limit = Keyword.get(opts, :limit)

    existing_count = Repo.aggregate(Phenology.Observation, :count)

    cond do
      dry_run? ->
        IO.puts("[dry-run] reading #{csv_path}, no rows will be inserted")

      reset? ->
        IO.puts("[reset] truncating phenology_observations + phenology_blacklist")
        Repo.query!("TRUNCATE phenology_observations, phenology_blacklist RESTART IDENTITY")

      existing_count > 0 ->
        Mix.raise(
          "phenology_observations already has #{existing_count} rows. " <>
            "Re-run with --reset to truncate first, or --dry-run to validate only."
        )

      true ->
        :ok
    end

    state = %{
      ok: 0,
      errors: [],
      processed: 0,
      progress_every: progress_every,
      dry_run: dry_run?
    }

    final =
      csv_path
      |> File.stream!()
      |> __MODULE__.Parser.parse_stream(skip_headers: false)
      |> Stream.with_index()
      |> then(fn s -> if limit, do: Stream.take(s, limit + 1), else: s end)
      |> Enum.reduce({nil, [], state}, &accumulate_row(&1, &2, batch_size))
      |> flush_remaining()

    print_summary(final)
  end

  # ----------------------------------------------------------------------
  # Streaming + batching
  # ----------------------------------------------------------------------

  defp accumulate_row({header_row, 0}, {_, _, state}, _batch_size) do
    # Preserve user-supplied state (dry_run, progress_every, etc.); only
    # capture the headers and clear the batch buffer.
    {header_row, [], state}
  end

  defp accumulate_row({row, _idx}, {headers, batch, state}, batch_size) do
    attrs = row_to_attrs(headers, row)
    batch = [attrs | batch]
    state = maybe_log(state)

    if length(batch) >= batch_size do
      state = insert_batch(batch, state)
      {headers, [], state}
    else
      {headers, batch, state}
    end
  end

  defp flush_remaining({headers, [], state}), do: {headers, [], state}

  defp flush_remaining({headers, batch, state}) do
    {headers, [], insert_batch(batch, state)}
  end

  # NB: `processed` is incremented in `maybe_log/1`, not here, so we don't
  # double-count.
  defp insert_batch(batch_reversed, %{dry_run: true} = state) do
    batch = Enum.reverse(batch_reversed)

    Enum.reduce(batch, state, fn attrs, st ->
      case Phenology.Observation.changeset(%Phenology.Observation{}, attrs) do
        %{valid?: true} -> %{st | ok: st.ok + 1}
        cs -> %{st | errors: [{attrs, cs} | st.errors]}
      end
    end)
  end

  defp insert_batch(batch_reversed, state) do
    batch = Enum.reverse(batch_reversed)

    {ok_delta, error_rows} =
      Repo.transaction(fn ->
        Enum.reduce(batch, {0, []}, fn attrs, {oks, errs} ->
          case Phenology.create_observation(attrs) do
            {:ok, _} -> {oks + 1, errs}
            {:error, cs} -> {oks, [{attrs, cs} | errs]}
          end
        end)
      end)
      |> elem(1)

    %{state | ok: state.ok + ok_delta, errors: error_rows ++ state.errors}
  end

  defp maybe_log(state) do
    new_processed = state.processed + 1

    if rem(new_processed, state.progress_every) == 0 do
      IO.puts("  ...#{new_processed} processed (#{state.ok} ok, #{length(state.errors)} errors)")
    end

    %{state | processed: new_processed}
  end

  # ----------------------------------------------------------------------
  # CSV row -> attrs
  # ----------------------------------------------------------------------

  defp row_to_attrs(headers, row) do
    Enum.zip(headers, row)
    |> Enum.reject(fn {key, _} -> key == "legacy_obs_id" end)
    |> Enum.into(%{}, fn {key, val} -> {String.to_atom(key), cast(key, val)} end)
  end

  defp cast(_key, ""), do: nil
  defp cast(_key, "NA"), do: nil

  defp cast(key, value) when key in ~w(species_id host_species_id doy inat_id) do
    String.to_integer(value)
  end

  defp cast(key, value)
       when key in ~w(latitude longitude raw_latitude raw_longitude seasind acchours) do
    {f, ""} = Float.parse(value)
    f
  end

  defp cast(key, value) when key in ~w(date raw_date) do
    Date.from_iso8601!(value)
  end

  defp cast(_key, value), do: value

  # ----------------------------------------------------------------------
  # Summary
  # ----------------------------------------------------------------------

  defp print_summary({_headers, _batch, state}) do
    IO.puts("")
    IO.puts("=== Import summary ===")
    IO.puts("  rows processed:  #{state.processed}")
    IO.puts("  inserted/valid:  #{state.ok}")
    IO.puts("  errors:          #{length(state.errors)}")

    if state.errors != [] do
      IO.puts("\nFirst 5 errors:")

      Enum.take(state.errors, 5)
      |> Enum.each(fn {attrs, cs} ->
        IO.puts(
          "  species=#{attrs[:species_id]} date=#{attrs[:date]} " <>
            "source=#{attrs[:source_type]} -> #{inspect(error_strings(cs))}"
        )
      end)
    end
  end

  defp error_strings(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
