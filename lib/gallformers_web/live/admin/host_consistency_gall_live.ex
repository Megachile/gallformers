defmodule GallformersWeb.Admin.HostConsistencyGallLive do
  @moduledoc """
  Per-gall deep-dive panel for host-association review.

  Shows, for a single gall: each structured host with its documented /
  undocumented status (Direction A), the plants named in the sources that have
  no association (Direction B), and the underlying source prose.

  Also hosts a write helper that drafts an iNaturalist-backed GF Note: the admin
  enters the gall's iNat taxon code, picks a host, opens a pre-filtered iNat
  Identify link (`taxon_id` + the "Host Plant ID" observation field), and pastes
  back an observation to generate the note text for GF Notes (source 58).
  """
  use GallformersWeb, :live_view

  alias Gallformers.Galls

  # The iNat "Host Plant ID" observation field, as a ready-to-use query-param key
  # (spaces pre-encoded; the colon is left literal, as iNat expects).
  @host_field "field:Host%20Plant%20ID"

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
     |> assign(:page_title, page_title(detail))
     |> assign(:draft_code, "")
     |> assign(:draft_host, "")
     |> assign(:draft_obs, "")}
  end

  @impl true
  def handle_event("update_draft", params, socket) do
    {:noreply,
     socket
     |> assign(:draft_code, params |> Map.get("code", "") |> String.trim())
     |> assign(:draft_host, Map.get(params, "host", ""))
     |> assign(:draft_obs, params |> Map.get("obs", "") |> String.trim())}
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
                <.link
                  navigate={gf_notes_path(@detail.gall_id, has_gf_notes?(@detail))}
                  class="hover:underline"
                >
                  Edit GF Notes
                </.link>
                <.link href={~p"/gall/#{@detail.gall_id}"} target="_blank" class="hover:underline">
                  Public page ↗
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
          
    <!-- Write helper: iNat-backed GF Note draft -->
          <section class="bg-white border border-gray-200 rounded shadow-sm">
            <div class="px-4 py-3 border-b border-gray-200 bg-gray-50">
              <h2 class="font-semibold text-gray-800">Draft an iNat-backed GF Note</h2>
              <p class="text-xs text-gray-500 mt-0.5">
                Cite an iNaturalist observation documenting this gall on a host, then copy the
                generated note into GF Notes.
              </p>
            </div>
            <div class="p-4 space-y-4">
              <form phx-change="update_draft" class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    1. iNat taxon code for <span class="italic">{@detail.gall_name}</span>
                  </label>
                  <div class="flex items-center gap-3">
                    <input
                      type="text"
                      name="code"
                      value={@draft_code}
                      inputmode="numeric"
                      placeholder="e.g. 123456"
                      autocomplete="off"
                      class="w-40 rounded border-gray-300 text-sm"
                    />
                    <a
                      href={gall_search_url(@detail.gall_name)}
                      target="_blank"
                      class="text-sm text-gf-maroon hover:underline"
                    >
                      Look up on iNaturalist ↗
                    </a>
                  </div>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    2. Host being added
                  </label>
                  <input
                    type="text"
                    name="host"
                    value={@draft_host}
                    list="host-candidates"
                    placeholder="e.g. Quercus margaretiae"
                    autocomplete="off"
                    class="w-72 rounded border-gray-300 text-sm"
                  />
                  <datalist id="host-candidates">
                    <option :for={name <- candidate_hosts(@detail)} value={name}></option>
                  </datalist>
                </div>

                <div :if={identify_url(@draft_code, @draft_host)}>
                  <label class="block text-sm font-medium text-gray-700 mb-1">
                    3. Find the observation
                  </label>
                  <a
                    href={identify_url(@draft_code, @draft_host)}
                    target="_blank"
                    class="inline-block text-sm text-gf-maroon hover:underline mb-2"
                  >
                    Open matching observations in the iNat Identify tool ↗
                  </a>
                  <input
                    type="text"
                    name="obs"
                    value={@draft_obs}
                    placeholder="Paste an observation URL or id"
                    autocomplete="off"
                    class="w-full rounded border-gray-300 text-sm"
                  />
                </div>

                <p
                  :if={
                    is_nil(identify_url(@draft_code, @draft_host)) and
                      (@draft_code != "" or @draft_host != "")
                  }
                  class="text-xs text-gray-500"
                >
                  Enter a numeric iNat code and a host to generate the observations link.
                </p>
              </form>

              <div :if={note_draft(@draft_host, @draft_obs)}>
                <label class="block text-sm font-medium text-gray-700 mb-1">
                  4. GF Note draft — copy into
                  <.link
                    navigate={gf_notes_path(@detail.gall_id, has_gf_notes?(@detail))}
                    class="text-gf-maroon hover:underline"
                  >
                    GF Notes
                  </.link>
                </label>
                <textarea
                  readonly
                  rows="3"
                  class="w-full rounded border-gray-300 bg-gray-50 text-sm"
                >{note_draft(@draft_host, @draft_obs)}</textarea>
              </div>
            </div>
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

  # --- iNat write helper -----------------------------------------------------

  # Host names worth citing tentatively: undocumented structured hosts + plants
  # named in the sources with no association. Deduped, alphabetical.
  defp candidate_hosts(detail) do
    undoc = detail.hosts |> Enum.reject(& &1.documented) |> Enum.map(& &1.host_name)
    mentions = Enum.map(detail.mentions, & &1.host_name)

    (undoc ++ mentions) |> Enum.uniq() |> Enum.sort()
  end

  defp gall_search_url(name),
    do: "https://www.inaturalist.org/search?q=#{URI.encode(name)}"

  # iNat Identify tool scoped to the gall taxon and the Host Plant ID field, per
  # the settled URL shape. `nil` until we have a numeric code and a host.
  defp identify_url(code, host) do
    if valid_code?(code) and host != "" do
      "https://www.inaturalist.org/observations/identify?taxon_id=#{code}" <>
        "&#{@host_field}=#{URI.encode(host)}"
    end
  end

  defp valid_code?(code), do: Regex.match?(~r/^\d+$/, code)

  # The drafted GF Note. `nil` until a host and an observation are supplied.
  defp note_draft(host, obs) do
    if host != "" and obs != "" do
      "#{host} added tentatively as a host based on this " <>
        "[iNat observation](#{normalize_obs_url(obs)})."
    end
  end

  # Accept a full URL, a bare observation id, or anything else pasted verbatim.
  defp normalize_obs_url(obs) do
    if Regex.match?(~r/^\d+$/, obs),
      do: "https://www.inaturalist.org/observations/#{obs}",
      else: obs
  end

  defp has_gf_notes?(detail), do: Enum.any?(detail.sources, &(&1.source_id == 58))

  # Direct GF Notes editor when notes exist, else the mapping list to add them.
  defp gf_notes_path(gall_id, true),
    do: ~p"/admin/species-sources/find?#{[species_id: gall_id, source_id: 58]}"

  defp gf_notes_path(gall_id, false),
    do: ~p"/admin/species-sources/find?#{[species_id: gall_id]}"
end
