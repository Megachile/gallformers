defmodule GallformersWeb.Admin.HostConsistencyLive do
  @moduledoc """
  Admin review queue for dangling host associations.

  Surfaces gall↔host associations whose host is not documented in the gall's
  source text (Direction A — `:undocumented_association`). Filterable by family
  or tribe on both the inducer (gall) and host sides so a taxon expert can work
  through their own group. All computed on demand — see
  `Gallformers.Galls.HostConsistency`.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Galls
  alias Gallformers.Taxonomy
  alias Gallformers.Taxonomy.Tree

  @notes_values ~w(any with without)

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:current_user, session["current_user"])
      |> assign(:page_title, "Host Association Review")
      |> assign(:gall_families, Taxonomy.list_families_for_select(:gall))
      |> assign(:host_families, Taxonomy.list_families_for_select(:plant))
      |> assign(:items, [])
      |> assign(:total, 0)
      |> assign(:truncated, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    gall_family = parse_int(params["gfam"])
    gall_tribe = parse_int(params["gtribe"])
    host_family = parse_int(params["hfam"])
    host_tribe = parse_int(params["htribe"])
    notes = parse_notes(params["notes"])

    socket =
      socket
      |> assign(:gall_family, gall_family)
      |> assign(:gall_tribe, gall_tribe)
      |> assign(:host_family, host_family)
      |> assign(:host_tribe, host_tribe)
      |> assign(:notes, notes)
      |> assign(:gall_tribes, tribe_options(gall_family))
      |> assign(:host_tribes, tribe_options(host_family))
      |> load_discrepancies()

    {:noreply, socket}
  end

  # --- Filter events (each patches the URL; handle_params recomputes) ---------

  @impl true
  def handle_event("gall_family", %{"value" => v}, socket),
    do: {:noreply, push_filter(socket, gfam: v, gtribe: nil)}

  @impl true
  def handle_event("gall_tribe", %{"value" => v}, socket),
    do: {:noreply, push_filter(socket, gtribe: v)}

  @impl true
  def handle_event("host_family", %{"value" => v}, socket),
    do: {:noreply, push_filter(socket, hfam: v, htribe: nil)}

  @impl true
  def handle_event("host_tribe", %{"value" => v}, socket),
    do: {:noreply, push_filter(socket, htribe: v)}

  @impl true
  def handle_event("notes", %{"value" => v}, socket),
    do: {:noreply, push_filter(socket, notes: v)}

  # --- Data ------------------------------------------------------------------

  defp load_discrepancies(socket) do
    filter = %{
      gall_taxon_id: socket.assigns.gall_tribe || socket.assigns.gall_family,
      host_taxon_id: socket.assigns.host_tribe || socket.assigns.host_family,
      has_gf_notes: socket.assigns.notes
    }

    result = Galls.host_discrepancies(filter)

    socket
    |> assign(:items, result.items)
    |> assign(:total, result.total)
    |> assign(:truncated, result.truncated)
  end

  defp tribe_options(nil), do: []

  defp tribe_options(family_id) do
    family_id
    |> Tree.list_intermediates_for_family()
    |> Enum.map(&{&1.name, &1.id})
    |> Enum.sort()
  end

  # --- URL params ------------------------------------------------------------

  defp push_filter(socket, overrides) do
    current = %{
      gfam: socket.assigns.gall_family,
      gtribe: socket.assigns.gall_tribe,
      hfam: socket.assigns.host_family,
      htribe: socket.assigns.host_tribe,
      notes: socket.assigns.notes
    }

    params =
      current
      |> Map.merge(Map.new(overrides))
      |> Enum.reduce(%{}, fn {k, v}, acc -> put_param(acc, k, v) end)

    push_patch(socket, to: ~p"/admin/host-consistency?#{params}")
  end

  defp put_param(acc, _k, nil), do: acc
  defp put_param(acc, _k, ""), do: acc
  defp put_param(acc, :notes, :any), do: acc
  defp put_param(acc, k, v), do: Map.put(acc, to_string(k), to_string(v))

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_notes(v) when v in @notes_values, do: String.to_existing_atom(v)
  defp parse_notes(_), do: :any

  defp any_filter?(assigns),
    do: not is_nil(assigns.gall_family) or not is_nil(assigns.host_family)

  # --- Render ----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <div class="max-w-7xl mx-auto">
        <div class="mb-4 p-3 bg-gray-50 border border-gray-200 rounded flex items-center gap-4">
          <span class="text-sm font-medium text-gray-700">Quick Links:</span>
          <.link navigate={~p"/admin"} class="text-sm hover:underline">← Back to Admin</.link>
          <.link navigate={~p"/admin/gallhost"} class="text-sm hover:underline">
            Gall-Host Mappings
          </.link>
        </div>

        <div class="bg-white border border-gray-200 rounded shadow-sm">
          <div class="px-4 py-3 border-b border-gray-200 bg-gray-50 flex items-center justify-between">
            <h4 class="text-lg font-semibold text-gf-maroon">Host Association Review</h4>
            <span class="text-sm text-gray-500">
              {@total} undocumented association{if @total == 1, do: "", else: "s"}
            </span>
          </div>

          <div class="p-4">
            <p class="text-sm text-gray-600 mb-4">
              Each row is a host in the <code>gallhost</code>
              table whose current name is <strong>not written</strong>
              in any of that gall's source descriptions. Resolve it by citing a source that names the
              host, adding a Gallformers Note explaining the association, or removing the association.
              Filter to a family or tribe you know to work through your own group.
            </p>

            <div class="mb-4 grid grid-cols-1 md:grid-cols-2 gap-4">
              <fieldset class="border border-gray-200 rounded p-3">
                <legend class="text-xs font-semibold text-gray-500 px-1">Inducer (gall)</legend>
                <div class="flex flex-wrap items-center gap-3">
                  <form phx-change="gall_family" class="w-48">
                    <.input
                      type="select"
                      name="value"
                      value={@gall_family}
                      options={[{"All families", ""} | @gall_families]}
                    />
                  </form>
                  <form :if={@gall_tribes != []} phx-change="gall_tribe" class="w-48">
                    <.input
                      type="select"
                      name="value"
                      value={@gall_tribe}
                      options={[{"All tribes", ""} | @gall_tribes]}
                    />
                  </form>
                </div>
              </fieldset>

              <fieldset class="border border-gray-200 rounded p-3">
                <legend class="text-xs font-semibold text-gray-500 px-1">Host (plant)</legend>
                <div class="flex flex-wrap items-center gap-3">
                  <form phx-change="host_family" class="w-48">
                    <.input
                      type="select"
                      name="value"
                      value={@host_family}
                      options={[{"All families", ""} | @host_families]}
                    />
                  </form>
                  <form :if={@host_tribes != []} phx-change="host_tribe" class="w-48">
                    <.input
                      type="select"
                      name="value"
                      value={@host_tribe}
                      options={[{"All tribes", ""} | @host_tribes]}
                    />
                  </form>
                </div>
              </fieldset>
            </div>

            <div class="mb-4 flex items-center gap-2">
              <label class="text-sm font-medium text-gray-700">GF Notes:</label>
              <form phx-change="notes" class="w-44">
                <.input
                  type="select"
                  name="value"
                  value={@notes}
                  options={[
                    {"Any", "any"},
                    {"Has GF Notes", "with"},
                    {"No GF Notes", "without"}
                  ]}
                />
              </form>
            </div>

            <p :if={not any_filter?(assigns)} class="text-sm text-gray-500 italic py-6 text-center">
              Choose an inducer or host family above to load the queue.
            </p>

            <div
              :if={@truncated}
              class="mb-3 p-2 bg-amber-50 border border-amber-200 rounded text-sm text-amber-800"
            >
              Showing the first {length(@items)} of {@total}. Narrow by tribe to see the rest.
            </div>

            <.table :if={any_filter?(assigns) and @items != []} id="host-consistency" rows={@items}>
              <:col :let={d} label="Gall">
                <.link navigate={~p"/admin/galls/#{d.gall_id}"} class="text-gf-maroon hover:underline">
                  {d.gall_name}
                </.link>
              </:col>
              <:col :let={d} label="Undocumented host">
                <.link navigate={~p"/admin/hosts/#{d.host_id}"} class="hover:underline">
                  {d.host_name}
                </.link>
                <span
                  :if={d.genus_placeholder}
                  class="ml-1 text-xs text-gray-400"
                  title="genus-level placeholder host"
                >
                  (genus)
                </span>
              </:col>
              <:col :let={d} label="Sources">
                <span class="text-sm text-gray-600">{d.source_count}</span>
                <span
                  :if={d.has_gf_notes}
                  class="ml-1 text-xs px-1.5 py-0.5 rounded bg-blue-100 text-blue-700"
                >
                  GF Notes
                </span>
              </:col>
              <:action :let={d}>
                <.link navigate={~p"/admin/gallhost?id=#{d.gall_id}"} class="text-sm hover:underline">
                  Edit hosts
                </.link>
              </:action>
              <:action :let={d}>
                <.link navigate={~p"/admin/galls/#{d.gall_id}"} class="text-sm hover:underline">
                  Edit gall & sources
                </.link>
              </:action>
            </.table>

            <p
              :if={any_filter?(assigns) and @items == []}
              class="text-sm text-green-700 py-6 text-center"
            >
              No undocumented associations in this scope. 🎉
            </p>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
