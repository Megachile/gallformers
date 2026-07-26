defmodule GallformersWeb.Admin.AuthorshipIssuesLive do
  @moduledoc """
  Authorship records that contradict each other or are malformed.

  Deliberately not a backlog of names lacking a source. Those number in the
  thousands and are the database being incomplete — a different and much
  larger job. Everything listed here is a defect in what has already been
  recorded, and each row is fixed by editing an entry or a source rather than
  by acquiring anything new. That keeps the page finishable.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Authorship

  @labels %{
    conflicting_attribution: "Readings disagree",
    ambiguous_basionym: "Two original descriptions",
    unrelated_establishing_name: "Name belongs to neither the species nor a synonym",
    contradicted_direct_entry: "Typed authorship contradicted by sources"
  }

  @explanations %{
    conflicting_attribution:
      "Two sources give this name a different author or year. Usually a transcription slip; occasionally a real nomenclatural question. Fix it in whichever entry is wrong, or on the source record if the year belongs to the publication.",
    ambiguous_basionym:
      "Two entries each claim to be the original description of a different name for this species. Both cannot be. Clear the establishing name from whichever entry is not it.",
    unrelated_establishing_name:
      "An entry records establishing a name that is neither this species' nor one of its synonyms. Usually a host plant or a line of prose read as a binomial. Clear it, or add the name as a synonym if it is genuinely one.",
    contradicted_direct_entry:
      "An authorship typed on the species that the sources now disagree with. The sourced value is already what displays; remove the typed one or correct the source."
  }

  @impl true
  def mount(_params, session, socket) do
    issues = Authorship.issues()

    {:ok,
     socket
     |> assign(:current_user, session["current_user"])
     |> assign(:page_title, "Authorship Issues")
     |> assign(:issues, issues)
     |> assign(:counts, Enum.frequencies_by(issues, & &1.type))
     |> assign(:filter, nil)}
  end

  @impl true
  def handle_event("filter", %{"type" => ""}, socket) do
    {:noreply, assign(socket, :filter, nil)}
  end

  def handle_event("filter", %{"type" => type}, socket) do
    {:noreply, assign(socket, :filter, String.to_existing_atom(type))}
  end

  def handle_event("refresh", _params, socket) do
    issues = Authorship.issues()

    {:noreply,
     socket
     |> assign(:issues, issues)
     |> assign(:counts, Enum.frequencies_by(issues, & &1.type))
     |> put_flash(:info, "Rechecked — #{length(issues)} issues")}
  end

  defp visible(issues, nil), do: issues
  defp visible(issues, filter), do: Enum.filter(issues, &(&1.type == filter))

  defp label(type), do: Map.get(@labels, type, to_string(type))
  defp explanation(type), do: Map.get(@explanations, type)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin page_title={@page_title} current_user={@current_user} flash={@flash}>
      <div class="max-w-6xl mx-auto">
        <div class="mb-4 p-3 bg-gray-50 border border-gray-200 rounded flex items-center gap-4">
          <span class="text-sm font-medium text-gray-700">Quick Links:</span>
          <.link navigate={~p"/admin"} class="text-sm hover:underline">&larr; Back to Admin</.link>
          <button type="button" phx-click="refresh" class="text-sm hover:underline">Recheck</button>
        </div>

        <p class="mb-4 text-sm text-gray-600 max-w-3xl">
          Authorship records that contradict each other or are malformed. Names that simply have no
          source establishing them are not listed — that is the database being incomplete rather
          than wrong, and there are thousands. Everything here is fixable by editing an entry or a
          source.
        </p>

        <div class="mb-4 flex flex-wrap gap-2">
          <button
            type="button"
            phx-click="filter"
            phx-value-type=""
            class={[
              "px-3 py-1.5 text-sm border rounded",
              is_nil(@filter) && "bg-gf-maroon text-white border-gf-maroon",
              !is_nil(@filter) && "bg-white border-gray-300 hover:border-gf-maroon"
            ]}
          >
            All ({length(@issues)})
          </button>
          <button
            :for={{type, count} <- Enum.sort_by(@counts, &elem(&1, 1), :desc)}
            type="button"
            phx-click="filter"
            phx-value-type={type}
            class={[
              "px-3 py-1.5 text-sm border rounded",
              @filter == type && "bg-gf-maroon text-white border-gf-maroon",
              @filter != type && "bg-white border-gray-300 hover:border-gf-maroon"
            ]}
          >
            {label(type)} ({count})
          </button>
        </div>

        <p
          :if={@filter}
          class="mb-4 p-3 text-sm bg-amber-50 border border-amber-200 rounded max-w-3xl"
        >
          {explanation(@filter)}
        </p>

        <div :if={@issues == []} class="p-8 text-center text-gray-500 border border-gray-200 rounded">
          Nothing contradictory on record. Names still lacking a source are not counted here.
        </div>

        <div class="space-y-3">
          <div
            :for={issue <- visible(@issues, @filter)}
            class="border border-gray-200 rounded bg-white p-3"
          >
            <div class="flex items-start justify-between gap-3">
              <div>
                <.link
                  navigate={~p"/admin/galls/#{issue.species_id}"}
                  class="text-gf-maroon hover:underline"
                >
                  <.taxon_name name={issue.species_name} />
                </.link>
                <span :if={issue.name != issue.species_name} class="text-sm text-gray-500">
                  &mdash; on <.taxon_name name={issue.name} />
                </span>
              </div>
              <span class="text-xs uppercase tracking-wide text-gray-500 whitespace-nowrap">
                {label(issue.type)}
              </span>
            </div>

            <p :if={issue.typed && issue.type == :contradicted_direct_entry} class="mt-1 text-sm">
              Typed on the species: <span class="font-medium">{issue.typed}</span>
            </p>

            <ul class="mt-2 space-y-1">
              <li :for={reading <- issue.readings} class="text-sm flex flex-wrap items-baseline gap-2">
                <span class="font-medium text-gray-800">{reading.authorship || "—"}</span>
                <span class="text-xs text-gray-500">{reading.role}</span>
                <span :if={reading.name != issue.name} class="text-xs text-gray-500">
                  as <em>{reading.name}</em>
                </span>
                <.link
                  navigate={
                    ~p"/admin/species-sources/find?species_id=#{issue.species_id}&source_id=#{reading.source_id}"
                  }
                  class="text-xs text-gf-maroon hover:underline"
                >
                  {reading.source_title}
                </.link>
                <.link
                  navigate={~p"/admin/sources/#{reading.source_id}"}
                  class="text-xs text-gray-500 hover:underline"
                >
                  source record
                </.link>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
