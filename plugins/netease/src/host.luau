--!strict

local netease = require("./netease")
local ui = tern.ui

type Player = netease.Player

type Meta = {
	album: string?,
	duration: number?,
	art_url: string?,
	song_id: number?,
	state: string,
	at: number,
}

local POLL_MS = 300
local VOLUME_STEP = 5
local OPTIMISTIC_MS = 4000
local FLASH_MS = 4000
local RESEND_MS = 1500
local META_TTL_S = 6 * 3600

type Block = {
	context: BlockCx,
	blob_key: string?,
	blob: string?,
	resend_at: number?,
	rendered: string,
}

-- Blocks have no close hook, so the loop drops panes that are gone
local blocks: { [number]: Block } = {}
local current_player: Player? = nil
local problem: string? = nil
local art: { key: string?, bytes: string?, mime: string? } = {}
local meta: { [string]: Meta } = {}
local optimistic: { [string]: { value: any, expires: number } } = {}
local sent: { [string]: number } = {}
local last_ack: string? = nil
local loop: TimerHandle? = nil

local function value(field: string, actual: any): any
	local pending = optimistic[field]
	if pending == nil then
		return actual
	end
	if tern.now() > pending.expires or pending.value == actual then
		optimistic[field] = nil
		return actual
	end
	return pending.value
end

local function status(): string
	return value("status", if current_player then current_player.status else "")
end

local function alive_panes(): { [number]: boolean }
	local live = {}
	for _, pane in tern.pane.list() do
		live[pane.pane] = true
	end
	return live
end

local function mime_of(bytes: string): string
	if string.sub(bytes, 1, 2) == "\xFF\xD8" then
		return "image/jpeg"
	end
	return "image/png"
end

local function share_art()
	if not art.bytes or not art.key then
		return
	end
	local now = tern.now()
	for _, block in blocks do
		if block.blob_key ~= art.key or (block.resend_at and now >= block.resend_at) then
			block.resend_at = if block.blob_key ~= art.key then now + RESEND_MS else nil
			block.blob = block.context:blob(art.bytes :: string, art.mime or "image/png")
			block.blob_key = art.key
			block.rendered = ""
		end
	end
end

local function render_all()
	for _, block in blocks do
		block.context:render()
	end
end

local function enc(text: string): string
	return (string.gsub(text, "[^%w%-%._~]", function(ch: string): string
		return string.format("%%%02X", string.byte(ch))
	end))
end

local function norm(text: string): string
	return (string.gsub(string.lower(text), "[%s%p]", ""))
end

local function meta_for(player: Player): Meta?
	local entry = meta[player.track]
	if entry == nil then
		return nil
	end
	if entry.state ~= "loading" and os.time() - entry.at > META_TTL_S then
		meta[player.track] = nil
		return nil
	end
	return entry
end

-- NetEase's public catalogue answers without a login: the search picks the song, the
-- song detail carries the cover URL and the length.
local function load_meta(player: Player)
	local track = player.track
	local known = if track == "" then nil else meta[track]
	if track == "" or (known and (known.state ~= "failed" or os.time() - known.at < 60)) then
		return
	end
	meta[track] = { state = "loading", at = os.time() }
	local query = player.title
	if player.artist ~= "" then
		query ..= " " .. player.artist
	end
	local headers = { ["User-Agent"] = "Mozilla/5.0", ["Referer"] = "https://music.163.com/" }
	tern.fetch(
		"https://music.163.com/api/search/get?type=1&limit=5&s=" .. enc(query),
		{ headers = headers, timeout_ms = 15000 },
		function(response: FetchResult, _)
			local ok, data = pcall(tern.json.decode, response.body)
			local songs = if ok and type(data) == "table" and type(data.result) == "table" then data.result.songs else nil
			if type(songs) ~= "table" or #songs == 0 then
				meta[track] = { state = "failed", at = os.time() }
				return
			end
			local picked = songs[1]
			local wanted = norm(player.title)
			for _, song in songs do
				if norm(song.name or "") == wanted then
					picked = song
					break
				end
			end
			meta[track] = {
				state = "ok",
				album = picked.album and picked.album.name or nil,
				duration = picked.duration,
				song_id = picked.id,
				at = os.time(),
			}
			local id = picked.id
			if type(id) ~= "number" then
				render_all()
				return
			end
			tern.fetch(
				"https://music.163.com/api/v3/song/detail?c=" .. enc('[{"id":' .. tostring(math.floor(id)) .. "}]"),
				{ headers = headers, timeout_ms = 15000 },
				function(detail: FetchResult, __)
					local current = meta[track]
					if current == nil or current.state ~= "ok" then
						return
					end
					local done, body = pcall(tern.json.decode, detail.body)
					local song = if done and type(body) == "table" and type(body.songs) == "table" then body.songs[1] else nil
					if type(song) ~= "table" then
						render_all()
						return
					end
					local album = song.al
					if type(album) == "table" then
						current.album = album.name or current.album
						current.art_url = album.picUrl
					end
					if song.dt then
						current.duration = song.dt
					end
					current.at = os.time()
					render_all()
					local url = current.art_url
					if url == nil or current_player == nil or current_player.track ~= track then
						return
					end
					tern.fetch(url .. "?param=512y512", { timeout_ms = 20000 }, function(image: FetchResult, ___)
						if image.error or image.status ~= 200 or image.body == "" then
							return
						end
						if current_player == nil or current_player.track ~= track then
							return
						end
						art = { key = track, bytes = image.body, mime = mime_of(image.body) }
						share_art()
						render_all()
					end)
				end
			)
		end
	)
end

local function report(player: Player)
	if player.ack == nil or player.ack == last_ack then
		return
	end
	last_ack = player.ack
	local pane = sent[player.ack]
	if pane == nil then
		return
	end
	sent[player.ack] = nil
	if player.error then
		optimistic = {}
		local block = blocks[pane]
		if block then
			block.context:toast("error", "NetEase", player.error)
		end
	end
end

local function send(block: Block?, name: string, arg: (string | number)?)
	local id = netease.send(name, arg)
	if block then
		sent[id] = block.context.pane
	end
end

local function expect(field: string, expected: any)
	optimistic[field] = { value = expected, expires = tern.now() + OPTIMISTIC_MS }
end

local function say(block: Block, text: string)
	block.context:toast("info", "NetEase", text)
end

local function toggle(block: Block)
	local player = current_player
	if not (player and player.running) then
		send(block, "open")
		return
	end
	send(block, "toggle")
	expect("status", if status() == "playing" then "paused" else "playing")
end

local function no_volume(player: Player?): string
	if player and player.running then
		return "NetEase's volume shows once it plays"
	end
	return "NetEase doesn't report its volume"
end

local function set_volume(block: Block, level: number)
	local player = current_player
	if not (player and player.can.volume) then
		say(block, no_volume(player))
		return
	end
	level = math.clamp(math.floor(level + 0.5), 0, 100)
	if value("muted", player.muted) then
		send(block, "mute", 0)
		expect("muted", false)
	end
	send(block, "volume", level)
	expect("volume", level)
end

local function mute(block: Block)
	local player = current_player
	if not (player and player.can.mute) then
		say(no_volume(player))
		return
	end
	local on = not value("muted", player.muted)
	send(block, "mute", if on then 1 else 0)
	expect("muted", on)
end

local function signature(): string
	local player = current_player
	local parts = {
		tostring(if player then player.seq else -1),
		status(),
	}
	local entry = if player then meta_for(player) else nil
	table.insert(parts, tostring(if entry then entry.album or "" else ""))
	table.insert(parts, tostring(if entry and entry.duration then entry.duration else 0))
	for field, pending in optimistic do
		table.insert(parts, field .. "=" .. tostring(pending.value))
	end
	return table.concat(parts, "|")
end

local function tick()
	loop = nil
	local live = alive_panes()
	for pane in blocks do
		if not live[pane] then
			blocks[pane] = nil
		end
	end
	if next(blocks) == nil then
		return
	end

	local latest = netease.read()
	problem = netease.ensure(latest)
	if latest and netease.is_fresh(latest) then
		current_player = latest
		if latest.track ~= "" then
			load_meta(latest)
		end
		share_art()
		report(latest)
	elseif latest and current_player == nil then
		current_player = latest
	end

	local render_signature = signature()
	for _, block in blocks do
		if block.rendered ~= render_signature then
			block.rendered = render_signature
			block.context:render()
		end
	end
	loop = tern.timer(POLL_MS, tick)
end

local function start_loop()
	if loop == nil then
		loop = tern.timer(0, tick)
	end
end

local function with(node: Node, props: { [string]: any }): Node
	local merged: { [string]: any } = node.p or {}
	for name, prop in props do
		merged[name] = prop
	end
	node.p = merged
	return node
end

local function button(key: string, icon: string, act: string, enabled: boolean, on: boolean?, label: string?): Node
	local kids: { Node } = { ui.node("icon", { name = icon }) }
	if label then
		table.insert(kids, ui.text({ ui.span(label, "strong") }))
	end
	local props: { [string]: any } = {
		key = key,
		role = if key == "play"
			then "netease-player__button netease-player__button--play netease-u-interactive"
			else "netease-player__button netease-u-interactive",
		tone = if not enabled then "muted" elseif on then "accent" else nil,
	}
	if enabled then
		props.actions = { click = act }
	end
	return with(ui.row(kids), props)
end

local function message(head: string, body: string, buttons: { Node }, tone: string?): Node
	local children: { Node } = { ui.md(body) }
	if #buttons > 0 then
		table.insert(children, with(ui.row(buttons), { key = "buttons" }))
	end
	return with(ui.card({ ui.span(head, "strong") }, children), { key = "message", tone = tone })
end

local function text_button(key: string, label: string, act: string, tone: string): Node
	return with(ui.badge(label, tone), {
		key = key,
		role = "netease-player__link netease-u-interactive",
		actions = { click = act },
	})
end

local function controls_row(player: Player): Node
	local playing = status() == "playing"
	return with(ui.row({
		button("prev", "frame-prev", "prev", player.can.prev),
		button("play", if playing then "pause" else "play", "play-pause", player.can.play),
		button("next", "frame-next", "next", player.can.next),
	}), { key = "controls", role = "netease-player__controls" })
end

local function cover(block: Block, player: Player, key: string, role: string, clickable: boolean): Node
	if block.blob and block.blob_key == player.track then
		local props: { [string]: any } = { key = key, role = role }
		if clickable then
			props.role = role .. " netease-u-interactive"
			props.actions = { click = "launch" }
		end
		return with(ui.node("image", { blob = block.blob, alt = player.title }), props)
	end
	return with(ui.node("icon", { name = "wave" }), { key = key, role = role .. " netease-player__cover--empty" })
end

local function now_playing(block: Block, player: Player, _context: BlockCx): Node
	local entry = meta_for(player)
	local facts: { string } = {}
	if entry and entry.album and entry.album ~= "" then
		table.insert(facts, entry.album)
	end
	if entry and entry.duration then
		table.insert(facts, netease.clock(entry.duration))
	end

	local meta_kids: { Node } = {
		with(ui.text({ ui.span(player.title, "strong") }), { key = "title", role = "netease-player__title" }),
	}
	if player.artist ~= "" then
		table.insert(meta_kids, with(ui.text(player.artist), { key = "artist", role = "netease-player__artist" }))
	end
	if #facts > 0 then
		table.insert(
			meta_kids,
			with(ui.text({ ui.span(table.concat(facts, " · "), "muted") }), { key = "album", role = "netease-player__album" })
		)
	end

	local muted = value("muted", player.muted) == true

	return with(ui.col({
		cover(block, player, "netease.backdrop", "netease-player__cover netease-player__backdrop", false),
		with(ui.col({ ui.text(" ") }), { key = "scrim", role = "netease-player__scrim" }),
		with(ui.row({
			cover(block, player, "netease.art", "netease-player__cover netease-player__art", true),
			with(ui.col(meta_kids), { key = "meta", role = "netease-player__meta" }),
			button("mute", if muted then "slash-circle" else "wave", "mute", player.can.mute, muted),
			controls_row(player),
		}), { key = "body", role = "netease-player__body" }),
	}), { key = "player", role = "netease-player" })
end

local function view(block: Block, context: BlockCx): BlockView
	local player = current_player
	local main: Node
	if problem and not netease.is_fresh(player) then
		main = message("NetEase helper not running", problem, { text_button("retry", "Retry", "retry", "accent") }, "error")
	elseif player == nil then
		main = with(ui.progress(nil, "Connecting to NetEase Cloud Music…"), { key = "message" })
	elseif player.problem then
		main = message("Can't reach NetEase", player.problem, { text_button("retry", "Retry", "retry", "accent") }, "warning")
	elseif not player.running then
		main = message(
			"NetEase Cloud Music isn't running",
			"Start the app on this machine and it shows up here.",
			{ text_button("open", "Open NetEase", "launch", "accent") },
			nil
		)
	elseif player.title == "" then
		main = message(
			"Nothing playing",
			"Pick something in NetEase Cloud Music.",
			{ text_button("open", "Open NetEase", "launch", "accent") },
			nil
		)
	else
		main = now_playing(block, player, context)
	end
	return {
		main = with(ui.col({ main }), { role = "netease-player__main" }),
	}
end

local function act(block: Block, name: string, arg: string?)
	local player = current_player
	if name == "play-pause" then
		toggle(block)
	elseif name == "next" then
		send(block, "next")
	elseif name == "prev" then
		send(block, "previous")
	elseif name == "mute" then
		mute(block)
	elseif name == "launch" then
		send(block, "open")
	elseif name == "retry" then
		netease.retry()
		problem = netease.ensure(netease.read())
	elseif name == "volume" then
		set_volume(block, (tonumber(arg) or 0) * 5)
	end
end

tern.block.define("player", {
	init = function(context: BlockCx, _args: { string }, _saved: any): Block
		local block: Block = { context = context, blob_key = nil, blob = nil, resend_at = nil, rendered = "" }
		blocks[context.pane] = block
		current_player = current_player or netease.read()
		start_loop()
		return block
	end,

	title = function(_block: Block): string?
		local player = current_player
		if player and player.running and player.title ~= "" then
			local symbol = if status() == "playing" then "▶ " else "⏸ "
			if player.artist ~= "" then
				return symbol .. netease.cut(player.artist, 30) .. " - " .. netease.cut(player.title, 40)
			end
			return symbol .. netease.cut(player.title, 40)
		end
		return "NetEase"
	end,

	view = function(block: Block, context: BlockCx): BlockView
		return view(block, context)
	end,

	key = function(block: Block, key: Key, _context: BlockCx): boolean?
		if key.ctrl or key.alt or key.meta then
			return false
		end
		local player = current_player
		local pressed = key.text or key.name
		if key.name == "space" or pressed == "k" then
			act(block, "play-pause")
		elseif pressed == "n" or pressed == "." then
			act(block, "next")
		elseif pressed == "p" or pressed == "," then
			act(block, "prev")
		elseif pressed == "+" or pressed == "=" or key.name == "up" then
			set_volume(block, (value("volume", player and player.volume) or 0) + VOLUME_STEP)
		elseif pressed == "-" or pressed == "_" or key.name == "down" then
			set_volume(block, (value("volume", player and player.volume) or 0) - VOLUME_STEP)
		elseif pressed == "m" then
			act(block, "mute")
		elseif pressed == "o" then
			act(block, "launch")
		else
			return false
		end
		return true
	end,

	event = function(block: Block, ui_event: UiEvent, _context: BlockCx)
		if ui_event.ev == "action" and type(ui_event.act) == "string" then
			act(block, ui_event.act, ui_event.value)
		end
	end,
})
