defmodule GallformersWeb.Admin.HostConsistencyGallLive do
  @moduledoc """
  Per-gall deep-dive panel for host-association review.

  Shows, for a single gall: each structured host with its documented /
  undocumented status (Direction A), the plants named in the sources that have
  no association (Direction B), and the underlying source prose. View-only — the
  write helpers (add host, draft GF Note) will live here later.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Galls

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign(socket, :current_user, session["current_user"])}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    detail = with {gall_id, ""} <- Integer.parse(id), do: Galls.host_consistency_detail(gall_id)

    {:noreply,
     socket
     |> assign(:detail, detail)
     |> assign(:page_title, page_title(detail))}
  end

  defp page_title(nil), do: "Gall not found"
  defp page_title(detail), do: "Review: #{detail.gall_name}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <div class="max-w-4xl mx-auto">
        <.link
          navigate={~p"/admin/host-consistency"}
          class="inline-flex items-center gap-1 text-sm text-gray-600 hover:text-gf-maroon mb-4"
        >
          <.icon name="ph-arrow-left" class="size-4" /> Back to the queue
        </.link>

        <div :if={is_nil(@detail)} class="bg-white border border-gray-200 rounded p-6 text-gray-600">
          That gall could not be found.
        </div>

        <div :if={@detail} class="space-y-6">
          <div class="bg-white border border-gray-200 rounded shadow-sm p-4">
            <div class="flex items-center justify-between">
              <h1 class="text-xl font-bold text-gf-maroon">{@detail.gall_name}</h1>
              <div class="flex gap-4 text-sm">
                <.link navigate={~p"/admin/gallhost?id=#{@detail.gall_id}"} class="hover:underline">
                  Edit hosts
                </.link>
                <.link navigate={~p"/admin/galls/#{@detail.gall_id}"} class="hover:underline">
                  Edit gall &amp; sources
                </.link>
              </div>
            </div>
          </div>
          
    <!-- Direction A: structured hosts -->
          <section class="bg-white border border-gray-200 rounded shadow-sm">
            <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
              <h2 class="font-semibold text-gray-800">
                Structured hosts
                <span class="text-sm font-normal text-gray-500">
                  ({undoc_count(@detail.hosts)} of {length(@detail.hosts)} not documented in sources)
                </span>
              </h2>
            </div>
            <ul class="divide-y divide-gray-100">
              <li :for={h <- @detail.hosts} class="px-4 py-2 flex items-center gap-3">
                <span
                  :if={h.documented}
                  class="text-xs px-1.5 py-0.5 rounded bg-green-100 text-green-700 w-24 text-center"
                >
                  documented
                </span>
                <span
                  :if={not h.documented}
                  class="text-xs px-1.5 py-0.5 rounded bg-amber-100 text-amber-800 w-24 text-center"
                >
                  undocumented
                </span>
                <.link navigate={~p"/admin/hosts/#{h.host_id}"} class="hover:underline">
                  {h.host_name}
                </.link>
                <span :if={h.genus_placeholder} class="text-xs text-gray-400">(genus)</span>
              </li>
              <li :if={@detail.hosts == []} class="px-4 py-3 text-sm text-gray-500 italic">
                No host associations recorded.
              </li>
            </ul>
          </section>
          
    <!-- Direction B: unassociated mentions -->
          <section class="bg-white border border-gray-200 rounded shadow-sm">
            <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
              <h2 class="font-semibold text-gray-800">
                Plants named in sources with no association
                <span class="text-sm font-normal text-gray-500">({length(@detail.mentions)})</span>
              </h2>
            </div>
            <ul class="divide-y divide-gray-100">
              <li :for={m <- @detail.mentions} class="px-4 py-2">
                <.link navigate={~p"/admin/hosts/#{m.host_id}"} class="hover:underline font-medium">
                  {m.host_name}
                </.link>
                <div :if={m.snippet != ""} class="text-xs text-gray-500 italic mt-0.5">
                  “{m.snippet}”
                </div>
              </li>
              <li :if={@detail.mentions == []} class="px-4 py-3 text-sm text-gray-500 italic">
                No unassociated plant mentions found in the sources.
              </li>
            </ul>
          </section>
          
    <!-- Source prose -->
          <section class="bg-white border border-gray-200 rounded shadow-sm">
            <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
              <h2 class="font-semibold text-gray-800">
                Source text
                <span class="text-sm font-normal text-gray-500">({length(@detail.sources)})</span>
              </h2>
            </div>
            <div class="divide-y divide-gray-100">
              <div :for={s <- @detail.sources} class="px-4 py-3">
                <div class="text-sm font-medium text-gray-700">{s.source_title}</div>
                <p class="text-sm text-gray-600 mt-1 whitespace-pre-wrap">{s.description}</p>
              </div>
              <div :if={@detail.sources == []} class="px-4 py-3 text-sm text-gray-500 italic">
                No source descriptions for this gall.
              </div>
            </div>
          </section>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  defp undoc_count(hosts), do: Enum.count(hosts, &(not &1.documented))
end
