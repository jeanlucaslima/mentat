defmodule MentatWeb.FeedComponents do
  use MentatWeb, :html

  attr :feed_entries, :list, required: true
  attr :nation_map, :map, required: true
  attr :filter_nation, :string, default: nil
  attr :filter_type, :atom, default: :all
  attr :filter_severity, :atom, default: :all
  attr :nations, :list, required: true
  attr :clickable, :boolean, default: false

  def feed_panel(assigns) do
    ~H"""
    <div>
      <h2 class="text-xs font-bold tracking-wider text-base-content/40 uppercase mb-4">
        Feed
      </h2>

      <%!-- Filter controls --%>
      <div class="flex flex-wrap items-center gap-2 mb-4">
        <%!-- Nation filter --%>
        <form phx-change="filter_feed" class="contents">
          <select
            name="nation"
            class="bg-base-300 border border-base-content/10 rounded px-2 py-1 text-xs text-base-content/70 focus:border-success focus:outline-none"
          >
            <option value="" selected={is_nil(@filter_nation)}>All nations</option>
            <option :for={n <- @nations} value={n} selected={@filter_nation == n}>{n}</option>
          </select>

          <%!-- Type filter --%>
          <input type="hidden" name="type" value={@filter_type} />
          <input type="hidden" name="severity" value={@filter_severity} />
        </form>

        <div class="flex items-center gap-1">
          <button
            :for={{value, label} <- [{:all, "All"}, {:events, "Events"}, {:actions, "Actions"}]}
            phx-click="filter_feed"
            phx-value-type={value}
            phx-value-nation={@filter_nation || ""}
            phx-value-severity={@filter_severity}
            class={[
              "px-2 py-1 text-xs rounded border transition-colors",
              if(@filter_type == value,
                do: "border-success bg-success/20 text-success",
                else: "border-base-content/10 text-base-content/40 hover:border-base-content/20"
              )
            ]}
          >
            {label}
          </button>
        </div>

        <div class="flex items-center gap-1">
          <button
            :for={{value, label} <- [{:all, "All"}, {:critical, "Critical"}]}
            phx-click="filter_feed"
            phx-value-severity={value}
            phx-value-nation={@filter_nation || ""}
            phx-value-type={@filter_type}
            class={[
              "px-2 py-1 text-xs rounded border transition-colors",
              if(@filter_severity == value,
                do: "border-success bg-success/20 text-success",
                else: "border-base-content/10 text-base-content/40 hover:border-base-content/20"
              )
            ]}
          >
            {label}
          </button>
        </div>
      </div>

      <%!-- Feed entries --%>
      <%= if @feed_entries == [] do %>
        <div class="text-base-content/40 text-sm">No activity yet</div>
      <% else %>
        <div class="space-y-1 max-h-[60vh] overflow-y-auto">
          <.feed_entry
            :for={entry <- @feed_entries}
            entry={entry}
            nation_map={@nation_map}
            clickable={@clickable}
          />
        </div>
      <% end %>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :nation_map, :map, required: true
  attr :clickable, :boolean, default: false

  def feed_entry(assigns) do
    ~H"""
    <%= if @clickable do %>
      <button
        phx-click="seek_to_tick"
        phx-value-tick={@entry.tick}
        class="flex items-start gap-2 text-sm w-full text-left hover:bg-base-content/5 rounded px-1 py-0.5 transition-colors"
      >
        <.feed_entry_content entry={@entry} nation_map={@nation_map} />
      </button>
    <% else %>
      <div class="flex items-start gap-2 text-sm px-1 py-0.5">
        <.feed_entry_content entry={@entry} nation_map={@nation_map} />
      </div>
    <% end %>
    """
  end

  attr :entry, :map, required: true
  attr :nation_map, :map, required: true

  defp feed_entry_content(assigns) do
    ~H"""
    <%!-- Nation color dot --%>
    <span
      class="inline-block w-2.5 h-2.5 rounded-full shrink-0 mt-1"
      style={"background-color: #{nation_color(@nation_map, @entry.nation_id)}"}
    >
    </span>

    <%!-- Tick info --%>
    <span class="text-base-content/40 font-mono text-xs shrink-0 mt-0.5 w-20">
      D{div(@entry.tick, 24)}·T{@entry.tick}
    </span>

    <%!-- Icon --%>
    <span class={["shrink-0 mt-0.5", entry_color(@entry)]}>
      <.icon name={entry_icon(@entry.sub_type)} class="size-3.5" />
    </span>

    <%!-- Content --%>
    <div class="min-w-0">
      <span class={["font-semibold uppercase text-xs", entry_color(@entry)]}>
        {format_sub_type(@entry.sub_type)}
      </span>
      <span class="text-base-content/70 ml-1 text-xs">{@entry.nation_id}</span>
      <div class="text-xs text-base-content/40 truncate">{format_detail(@entry)}</div>
    </div>
    """
  end

  defp nation_color(nation_map, nation_id) do
    case Map.get(nation_map, nation_id) do
      %{color: color} -> color
      _ -> "#6b7280"
    end
  end

  defp format_sub_type(sub_type) do
    sub_type
    |> String.replace("_", " ")
  end

  @doc false
  def entry_color(%{entry_type: "action", status: "failed"}), do: "text-error/60"
  def entry_color(%{entry_type: "action"}), do: "text-base-content/60"
  def entry_color(%{sub_type: "coup"}), do: "text-error"
  def entry_color(%{sub_type: "nation_collapsed"}), do: "text-error"
  def entry_color(%{sub_type: "default"}), do: "text-error"
  def entry_color(%{sub_type: "famine"}), do: "text-warning"
  def entry_color(%{sub_type: "battle"}), do: "text-warning"
  def entry_color(%{sub_type: "war_declared"}), do: "text-error"
  def entry_color(%{sub_type: "territory_conquered"}), do: "text-success"
  def entry_color(%{sub_type: "peace_treaty"}), do: "text-info"
  def entry_color(_), do: "text-base-content/70"

  defp entry_icon("move_troops"), do: "hero-arrow-path-micro"
  defp entry_icon("war_declared"), do: "hero-bolt-micro"
  defp entry_icon("battle"), do: "hero-fire-micro"
  defp entry_icon("territory_conquered"), do: "hero-flag-micro"
  defp entry_icon("peace_treaty"), do: "hero-shield-check-micro"
  defp entry_icon("famine"), do: "hero-exclamation-triangle-micro"
  defp entry_icon("default"), do: "hero-exclamation-triangle-micro"
  defp entry_icon("coup"), do: "hero-x-circle-micro"
  defp entry_icon("nation_collapsed"), do: "hero-x-circle-micro"
  defp entry_icon(_), do: "hero-information-circle-micro"

  defp format_detail(%{sub_type: "move_troops", payload: p, status: "failed", reason: reason}) do
    count = p["count"] || Map.get(p, :count, 0)
    from = p["from"] || Map.get(p, :from, "?")
    to = p["to"] || Map.get(p, :to, "?")
    "#{count} troops: #{from} \u2192 #{to} (failed: #{reason || "unknown"})"
  end

  defp format_detail(%{sub_type: "move_troops", payload: p}) do
    count = p["count"] || Map.get(p, :count, 0)
    from = p["from"] || Map.get(p, :from, "?")
    to = p["to"] || Map.get(p, :to, "?")
    "#{count} troops: #{from} \u2192 #{to}"
  end

  defp format_detail(%{sub_type: "coup", payload: p}) do
    old_gov = p["old_government"] || Map.get(p, :old_government, "?")
    new_gov = p["new_government"] || Map.get(p, :new_government, "?")
    "#{old_gov} \u2192 #{new_gov}"
  end

  defp format_detail(%{sub_type: "famine"}), do: "grain depleted"
  defp format_detail(%{sub_type: "default"}), do: "treasury below zero"

  defp format_detail(%{sub_type: "nation_collapsed", payload: p}) do
    pop = p["population"] || Map.get(p, :population, 0)
    "population: #{pop}"
  end

  defp format_detail(%{sub_type: "war_declared", payload: p}) do
    declared_by = p["declared_by"] || Map.get(p, :declared_by, "?")
    target = p["target"] || Map.get(p, :target, "?")
    "#{declared_by} vs #{target}"
  end

  defp format_detail(%{sub_type: "peace_treaty", payload: p}) do
    a = p["nation_a"] || Map.get(p, :nation_a, "?")
    b = p["nation_b"] || Map.get(p, :nation_b, "?")
    "#{a} \u2194 #{b}"
  end

  defp format_detail(%{sub_type: "territory_conquered", payload: p}) do
    tile = p["tile_id"] || Map.get(p, :tile_id, "?")
    prev = p["previous_owner"] || Map.get(p, :previous_owner, "?")
    "#{tile} conquered from #{prev}"
  end

  defp format_detail(%{sub_type: "battle", payload: p}) do
    tile = p["tile_id"] || Map.get(p, :tile_id, "?")
    attacker = p["attacker"] || Map.get(p, :attacker, "?")
    winner = p["winner"] || Map.get(p, :winner, "?")
    "#{attacker} at #{tile}, #{winner} wins"
  end

  defp format_detail(_), do: ""
end
