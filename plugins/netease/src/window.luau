--!strict

local netease = require("./netease")

local KIND = "netease.player"
local POLL_MS = 1000

local segment: StatusSegment? = nil
local sent: { [string]: boolean } = {}
local last_ack: string? = nil

local function float(cx: WindowCx, pane: number)
	local info = cx.session:pane(pane)
	if info and info.block == KIND and not info.floating then
		cx.layout:float(pane, nil, "br")
	end
end

tern.on("pane_created", function(event: PaneEvent, cx: WindowCx)
	float(cx, event.pane)
end)

local function open_player(cx: WindowCx)
	for _, pane in cx.session:panes() do
		if pane.block == KIND then
			cx.layout:focus(pane.pane)
			return
		end
	end
	-- Empty the cwd so Tern prints no directory in the picture in picture title strip.
	local target = cx.session:focused()
	local pane = if target
		then cx.layout:split(target, "right", { block = KIND, cwd = "" })
		else cx:new_block(KIND, nil, "beside")
	if pane == nil then
		cx:toast("error", "NetEase isn't loaded on this host", "Install the plugin where your panes run.")
		return
	end
	float(cx, pane)
end

tern.command({
	id = "open",
	title = "NetEase: Open player",
	icon = "wave",
	group = "NetEase",
	run = open_player,
})

if tern.runtime.os == "ios" then
	return
end

local function send(name: string, arg: (string | number)?)
	sent[netease.send(name, arg)] = true
end

local function command(id: string, title: string, icon: string, run: (player: netease.Player?) -> ())
	tern.command({
		id = id,
		title = title,
		icon = icon,
		group = "NetEase",
		run = function(_cx: WindowCx)
			run(netease.read())
		end,
	})
end

command("play-pause", "NetEase: Play/Pause", "play", function(player)
	if player and netease.is_fresh(player) and not player.running then
		send("open")
	else
		send("toggle")
	end
end)

command("next", "NetEase: Next track", "frame-next", function(_player)
	send("next")
end)

command("previous", "NetEase: Previous track", "frame-prev", function(_player)
	send("previous")
end)

command("mute", "NetEase: Mute/Unmute", "slash-circle", function(player)
	send("mute", if player and player.muted then 0 else 1)
end)

local function segment_of(player: netease.Player?): StatusSegment?
	if not (player and netease.is_fresh(player) and player.running and player.title ~= "") then
		return nil
	end
	local playing = player.status == "playing"
	local text = netease.cut(player.title, 32)
	if player.artist ~= "" then
		text ..= " · " .. netease.cut(player.artist, 24)
	end
	return {
		text = text,
		icon = if playing then "play" else "pause",
		tone = if playing then nil else "muted",
		command = "plugin.netease.open",
	}
end

tern.chrome.status(function(_pane: StatusPaneInfo): { StatusSegment }?
	return if segment then { segment :: StatusSegment } else nil
end)

local function is_same(left: StatusSegment?, right: StatusSegment?): boolean
	if left == nil or right == nil then
		return left == right
	end
	return left.text == right.text and left.icon == right.icon and left.tone == right.tone
end

local function tick(cx: WindowCx?)
	local player = netease.read()
	if cx then
		local ok, shown = pcall(function()
			return cx.settings:get("status_bar")
		end)
		if not ok or shown ~= false then
			netease.ensure(player)
		end
		if player and player.ack and player.ack ~= last_ack then
			last_ack = player.ack
			if sent[player.ack] then
				sent[player.ack] = nil
				if player.error then
					cx:toast("error", "NetEase", player.error)
				end
			end
		end
	end
	local next_segment = segment_of(player)
	if not is_same(next_segment, segment) then
		segment = next_segment
		tern.chrome.refresh()
	end
	tern.timer(POLL_MS, tick)
end

tern.timer(POLL_MS, tick)
