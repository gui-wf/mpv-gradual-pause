-- gradual_pause.lua — ease audio (and optionally the picture) on pause/unpause
-- version: 1.1.0
-- homepage: https://github.com/gui-wf/mpv-gradual-pause
-- license: MIT
--
-- mpv's volume property is cubic in gain (gain = (volume/100)^3). The default
-- ramp moves loudness evenly in decibels and only eases the corners, so the
-- fade is audible the whole way and does not click. A keyboard pause keeps
-- playback running through the fade-out, then pauses. An external pause
-- (MPRIS, OSC) has already stopped playback; the script does not resume it
-- for the fade. While that pause holds, audible volume stays 0 so a later
-- unpause cannot start at full volume. Resume continues from the paused
-- frame. Seeking back to the pre-fade timestamp restarted the decoder, cut
-- the picture, and threw away seeks made while paused.
-- restore_position=yes opts into that seek, and still yields if the paused
-- position moved.

local mp = require 'mp'
local options = require 'mp.options'
local msg = require 'mp.msg'

local SCRIPT_VERSION = "1.1.0"

local opts = {
    fade_out_duration = 0.45,  -- seconds, playing while volume eases to silence
    fade_in_duration = 0.45,   -- seconds, silence eases back to the saved volume
    steps = 12,                -- legacy hint; the ramp is never coarser than 20ms
    fade_curve = "auto",       -- auto | smooth | linear | logarithmic
    logarithmic_fade = true,   -- legacy: auto+yes → smooth, auto+no → linear
    video_transition = "soft", -- none | dim | blur | soft
    video_hold = false,        -- keep the softened look while paused
    blur_strength = 28,        -- peak negative sharpen; legacy vo=gpu only
    dim_strength = 22,         -- peak equalizer dip (contrast / saturation / brightness)
    restore_position = false,  -- seek back to the pre-fade time on unpause
    debug_mode = false,
}

local POSITION_SLACK = 0.25
local MIN_TICK = 0.008
local MAX_TICK = 0.020
local SMOOTH_FLOOR_DB = -36
local LOG_FLOOR_DB = -48

local base_volume = nil
local level = 1
local phase = nil -- "out", "in", or nil
local phase_origin = 1
local phase_target = 0
local phase_started = 0
local phase_dur = 0
local fade_timer = nil
-- One outstanding script pause write, not a count. mpv may coalesce opposite
-- writes into a single notification, or into none, so a counter leaks.
local pause_epoch = 0
local pause_pending = nil -- { epoch, value }
local pause_ack = nil -- last value already reconciled, same epoch
local pause_ready = false
local quiet_hold = false -- audible volume is pinned at 0 while paused
local active_file = false
local held_soft = false
local anchor_pos = nil
local paused_pos = nil
local video_saved = nil
local video_goal = nil
local failed_props = {}
local logged_blur_fallback = false

local function debug_log(message)
    if opts.debug_mode then
        msg.info(message)
    end
end

local function clamp(value, lo, hi)
    if value ~= value then
        return lo
    end
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function clamp01(value)
    return clamp(value, 0, 1)
end

function validate_options()
    if opts.fade_out_duration < 0 or opts.fade_out_duration > 5 then
        msg.warn("fade_out_duration should be between 0 and 5 seconds, got "
            .. tostring(opts.fade_out_duration))
        opts.fade_out_duration = clamp(opts.fade_out_duration, 0, 5)
    end

    if opts.fade_in_duration < 0 or opts.fade_in_duration > 5 then
        msg.warn("fade_in_duration should be between 0 and 5 seconds, got "
            .. tostring(opts.fade_in_duration))
        opts.fade_in_duration = clamp(opts.fade_in_duration, 0, 5)
    end

    opts.steps = math.floor(tonumber(opts.steps) or 12)
    if opts.steps < 1 or opts.steps > 100 then
        msg.warn("steps should be between 1 and 100, got " .. tostring(opts.steps))
        opts.steps = clamp(opts.steps, 1, 100)
    end

    local curves = { auto = true, smooth = true, linear = true, logarithmic = true }
    if not curves[opts.fade_curve] then
        msg.warn("fade_curve should be auto, smooth, linear, or logarithmic, got "
            .. tostring(opts.fade_curve))
        opts.fade_curve = "auto"
    end

    local modes = { none = true, dim = true, blur = true, soft = true }
    if not modes[opts.video_transition] then
        msg.warn("video_transition should be none, dim, blur, or soft, got "
            .. tostring(opts.video_transition))
        opts.video_transition = "soft"
    end

    opts.blur_strength = clamp(tonumber(opts.blur_strength) or 0, 0, 100)
    opts.dim_strength = clamp(tonumber(opts.dim_strength) or 0, 0, 100)

    debug_log("Configuration: fade_out=" .. opts.fade_out_duration
        .. "s, fade_in=" .. opts.fade_in_duration
        .. "s, steps=" .. opts.steps
        .. ", curve=" .. opts.fade_curve
        .. ", logarithmic_fade=" .. tostring(opts.logarithmic_fade)
        .. ", video=" .. opts.video_transition
        .. ", hold=" .. tostring(opts.video_hold)
        .. ", restore_position=" .. tostring(opts.restore_position))
end

options.read_options(opts, "gradual_pause", function()
    validate_options()
end)

local function resolved_curve()
    if opts.fade_curve == "auto" then
        if opts.logarithmic_fade then
            return "smooth"
        end
        return "linear"
    end
    return opts.fade_curve
end

-- Progress 0..1 with flat slope at the ends and slope 1 through the middle,
-- so a decibel ramp does not corner and does not sit in silence.
local function cornered(t)
    t = clamp01(t)
    local edge = 0.16
    if t < edge then
        local u = t / edge
        return edge * (2 * u * u - u * u * u)
    end
    if t > 1 - edge then
        local u = (1 - t) / edge
        return 1 - edge * (2 * u * u - u * u * u)
    end
    return t
end

-- Volume multiplier between `origin` and `target` (both fractions of the
-- saved volume). smooth / logarithmic interpolate in decibels relative to
-- that saved volume, then convert back through the inverse of mpv's cube.
local function multiplier_for(origin, target, t, kind)
    t = clamp01(t)
    if kind == "linear" then
        return origin + (target - origin) * t
    end

    local floor_db = SMOOTH_FLOOR_DB
    if kind == "logarithmic" then
        floor_db = LOG_FLOOR_DB
    end

    local function to_db(lv)
        if lv <= 0.0000001 then
            return floor_db
        end
        local db = 60 * math.log(lv) / math.log(10)
        if db < floor_db then
            return floor_db
        end
        return db
    end

    local function from_db(db)
        if db <= floor_db + 0.05 then
            return 0
        end
        return 10 ^ (db / 60)
    end

    local db = to_db(origin) + (to_db(target) - to_db(origin)) * cornered(t)
    return clamp01(from_db(db))
end

local function no_osd_set(name, value)
    if failed_props[name] then
        return
    end
    local ok, err = mp.commandv("no-osd", "set", name, string.format("%.4f", value))
    if ok == nil and err then
        failed_props[name] = true
        msg.warn("stopping updates to " .. name .. ": " .. tostring(err))
    end
end

local function reset_pause_ack()
    pause_epoch = pause_epoch + 1
    pause_pending = nil
    pause_ack = nil
end

local function set_pause(value)
    if mp.get_property_bool("pause") == value then
        -- Already there. An earlier opposite write in this turn will not be
        -- delivered if the net value matches the last notification.
        pause_pending = nil
        return
    end
    local epoch = pause_epoch
    pause_pending = { epoch = epoch, value = value }
    mp.set_property_bool("pause", value)
    -- If the notification is coalesced away, drop the pending ack once the
    -- property has the value we wrote. A later delivery of that same value is
    -- still ours (`pause_ack`). A different value is not.
    mp.add_timeout(0, function()
        if pause_epoch ~= epoch or not pause_pending then
            return
        end
        if pause_pending.epoch ~= epoch or pause_pending.value ~= value then
            return
        end
        if mp.get_property_bool("pause") == value then
            pause_ack = { epoch = epoch, value = value }
        end
        pause_pending = nil
    end)
end

local function consume_script_pause(value)
    if pause_pending and pause_pending.epoch == pause_epoch
        and pause_pending.value == value then
        pause_ack = { epoch = pause_epoch, value = value }
        pause_pending = nil
        return true
    end
    if pause_ack and pause_ack.epoch == pause_epoch and pause_ack.value == value then
        pause_ack = nil
        return true
    end
    pause_pending = nil
    pause_ack = nil
    return false
end

local function stop_timer()
    if fade_timer then
        fade_timer:kill()
        fade_timer = nil
    end
end

local function interval_for(duration)
    local requested = duration / math.max(1, opts.steps)
    return clamp(requested, MIN_TICK, MAX_TICK)
end

local function has_video()
    local track = mp.get_property_native("current-tracks/video")
    if type(track) == "table" then
        return true
    end
    local width = mp.get_property_number("video-params/w")
    return width ~= nil and width > 0
end

local function vo_supports_blur()
    -- `sharpen` is a legacy vo=gpu control. gpu-next never applied it, and
    -- current mpv removed the property. Dim still runs on those VOs.
    if (mp.get_property("current-vo") or "") ~= "gpu" then
        return false
    end
    return mp.get_property_number("sharpen") ~= nil
end

local function restore_video()
    if not video_saved then
        held_soft = false
        return
    end
    for name, orig in pairs(video_saved) do
        no_osd_set(name, orig)
    end
    video_saved = nil
    video_goal = nil
    held_soft = false
end

local function capture_video()
    if video_saved or opts.video_transition == "none" or not has_video() then
        return
    end

    local mode = opts.video_transition
    local blur_ok = vo_supports_blur()
    local want_blur = (mode == "blur" or mode == "soft") and opts.blur_strength > 0
    local want_dim = mode == "dim" or mode == "soft"

    if want_blur and not blur_ok then
        if not logged_blur_fallback then
            logged_blur_fallback = true
            debug_log("current VO cannot blur via sharpen; using the equalizer dip")
        end
        want_blur = false
        if mode == "blur" then
            want_dim = true
        end
    end

    local saved = {}
    local goal = {}

    local function track(name, delta)
        if math.abs(delta) < 0.05 then
            return
        end
        local orig = mp.get_property_number(name)
        if orig == nil then
            return
        end
        local target = clamp(orig + delta, -100, 100)
        if math.abs(target - orig) < 0.05 then
            return
        end
        saved[name] = orig
        goal[name] = target
    end

    if want_dim and opts.dim_strength > 0 then
        track("contrast", -opts.dim_strength * 0.45)
        track("saturation", -opts.dim_strength)
        track("brightness", -opts.dim_strength * 0.15)
    end
    if want_blur then
        track("sharpen", -opts.blur_strength)
    end

    if next(saved) == nil then
        return
    end

    video_saved = saved
    video_goal = goal
    debug_log("Video ease armed (" .. mode .. ")")
end

local function apply_softness(amount)
    if not video_saved then
        return
    end
    amount = clamp01(amount)
    for name, orig in pairs(video_saved) do
        local target = video_goal[name]
        no_osd_set(name, orig + (target - orig) * amount)
    end
end

local function softness_for(lv)
    lv = clamp01(lv)
    if opts.video_hold then
        return 1 - lv
    end
    -- Peak in the middle of the ramp so a settled pause is a clear still.
    return math.sin(math.pi * lv)
end

local function capture_volume()
    local vol = mp.get_property_number("volume")
    if vol ~= nil and vol >= 0 then
        base_volume = vol
        debug_log(string.format("Saved volume: %.2f", base_volume))
    end
end

local function is_natural_stop()
    if mp.get_property_bool("eof-reached") then
        return true
    end
    if mp.get_property_bool("idle-active") then
        return true
    end
    local path = mp.get_property("path")
    if path == nil or path == "" then
        return true
    end
    return false
end

local function maybe_restore_position()
    if not opts.restore_position then
        anchor_pos = nil
        paused_pos = nil
        return
    end
    if anchor_pos == nil or paused_pos == nil then
        return
    end
    if mp.get_property_bool("seeking") then
        debug_log("Skip position restore; a seek is in flight")
        anchor_pos = nil
        paused_pos = nil
        return
    end

    local now = mp.get_property_number("time-pos")
    if now == nil then
        anchor_pos = nil
        paused_pos = nil
        return
    end

    if math.abs(now - paused_pos) > POSITION_SLACK then
        debug_log(string.format(
            "Keeping seek made while paused (%.3f, paused at %.3f)",
            now, paused_pos))
        anchor_pos = nil
        paused_pos = nil
        return
    end

    if math.abs(now - anchor_pos) < 0.05 then
        anchor_pos = nil
        paused_pos = nil
        return
    end

    debug_log(string.format("Restoring pre-fade position %.3f", anchor_pos))
    no_osd_set("time-pos", anchor_pos)
    anchor_pos = nil
    paused_pos = nil
end

-- Pin audible volume at 0 without forgetting the user's level. External
-- unpause then starts silent, before this script's observer runs.
local function hold_quiet()
    if not quiet_hold then
        local vol = mp.get_property_number("volume")
        if vol and vol > 0.5 then
            base_volume = vol
        end
    end
    quiet_hold = true
    level = 0
    no_osd_set("volume", 0)
end

local function finish_fade()
    local direction = phase
    if not direction then
        return
    end
    phase = nil
    stop_timer()

    if direction == "out" then
        level = 0
        hold_quiet()
        if opts.video_hold and video_saved then
            apply_softness(1)
            held_soft = true
        else
            restore_video()
        end
        paused_pos = mp.get_property_number("time-pos")
        debug_log(string.format("Fade-out complete, pausing at %.3f",
            paused_pos or -1))
        if not mp.get_property_bool("pause") then
            set_pause(true)
        end
    else
        level = 1
        quiet_hold = false
        if base_volume then
            no_osd_set("volume", base_volume)
        end
        restore_video()
        anchor_pos = nil
        paused_pos = nil
        debug_log("Fade-in complete")
    end
end

local function on_tick()
    if not phase then
        return
    end

    local elapsed = mp.get_time() - phase_started
    local t = 1
    if phase_dur > 0 then
        t = clamp01(elapsed / phase_dur)
    end
    level = multiplier_for(phase_origin, phase_target, t, resolved_curve())

    if quiet_hold then
        no_osd_set("volume", 0)
    elseif base_volume and base_volume > 0 then
        no_osd_set("volume", math.max(0, base_volume * level))
    end
    apply_softness(softness_for(level))

    if opts.debug_mode then
        debug_log(string.format("%s t=%.3f level=%.3f volume=%.2f",
            phase == "out" and "Fade-out" or "Fade-in",
            elapsed, level, mp.get_property_number("volume") or -1))
    end

    if t >= 1 then
        finish_fade()
    end
end

local function arm_timer(direction, origin, target, full)
    local span = math.abs(target - origin)
    phase = direction
    phase_origin = origin
    phase_target = target
    phase_started = mp.get_time()
    phase_dur = full * span

    debug_log(string.format("Starting fade-%s from %.2f to %.2f over %.3fs (%s)",
        direction == "out" and "out" or "in",
        origin, target, phase_dur, resolved_curve()))

    if full <= 0 or span < 0.001 then
        level = target
        finish_fade()
        return
    end
    if phase_dur < 0.02 then
        phase_dur = 0.02
    end

    stop_timer()
    fade_timer = mp.add_periodic_timer(interval_for(phase_dur), on_tick)
end

local function begin_fade(direction)
    if not active_file then
        return
    end

    -- End of file already stopped playback. Do not unpause it to fade.
    if direction == "out" and is_natural_stop() then
        debug_log("Ignoring pause caused by end of file or idle")
        stop_timer()
        phase = nil
        restore_video()
        if quiet_hold then
            quiet_hold = false
            if base_volume then
                no_osd_set("volume", base_volume)
            end
        end
        return
    end

    -- External pause (or any pause that is already in effect). Resuming here
    -- would play past the pause request for the whole fade.
    if direction == "out" and mp.get_property_bool("pause") then
        stop_timer()
        phase = nil
        if anchor_pos == nil then
            anchor_pos = mp.get_property_number("time-pos")
        end
        hold_quiet()
        if not held_soft then
            capture_video()
        end
        paused_pos = mp.get_property_number("time-pos")
        if video_saved and opts.fade_out_duration > 0 then
            debug_log("Picture ease while paused; audio stays stopped")
            arm_timer("out", 1, 0, opts.fade_out_duration)
        else
            if opts.video_hold and video_saved then
                apply_softness(1)
                held_soft = true
            else
                restore_video()
            end
        end
        return
    end

    if direction == "out" and phase == "out" then
        return
    end
    if direction == "in" and phase == "in" then
        return
    end

    -- Reversing a keyboard fade-out that is still playing: keep the current
    -- level. Every other fade-in starts from silence.
    local reversing = direction == "in" and phase == "out" and not quiet_hold

    if direction == "out" and phase == nil then
        capture_volume()
        anchor_pos = mp.get_property_number("time-pos")
        if anchor_pos then
            debug_log(string.format("Fade-out anchor: %.3f", anchor_pos))
        end
        if not held_soft then
            capture_video()
        end
        if (base_volume or 0) <= 0 then
            hold_quiet()
            set_pause(true)
            return
        end
    end

    if direction == "in" and not reversing then
        if not quiet_hold then
            capture_volume()
        end
        if not video_saved and not held_soft then
            capture_video()
        end
        level = 0
        if base_volume and base_volume > 0 then
            no_osd_set("volume", 0)
        end
        maybe_restore_position()
        quiet_hold = false
    end

    if direction == "in" and mp.get_property_bool("pause") then
        set_pause(false)
    end

    local target = direction == "out" and 0 or 1
    local full = direction == "out" and opts.fade_out_duration or opts.fade_in_duration
    arm_timer(direction, level, target, full)
end

local function handle_pause_key()
    if not active_file then
        return
    end

    -- At EOF / idle the forced binding would swallow mpv's own toggle.
    -- Perform that toggle ourselves and let the observer ignore the write.
    if phase == nil and is_natural_stop() then
        debug_log("EOF/idle pause key; toggling without a fade")
        set_pause(not mp.get_property_bool("pause"))
        return
    end

    if phase == "out" then
        begin_fade("in")
    elseif phase == "in" then
        begin_fade("out")
    elseif mp.get_property_bool("pause") then
        begin_fade("in")
    else
        begin_fade("out")
    end
end

local function on_pause_change(_, value)
    -- The initial notification is the current value, not a user action.
    -- Treating it as unpause used to slam volume to 0 at the start of every file.
    if not pause_ready then
        pause_ready = true
        debug_log("Ignoring initial pause observation (" .. tostring(value) .. ")")
        -- Already paused when the script loads (for example `--pause`).
        -- Hold silence so a later external unpause does not start at full volume.
        if value == true and active_file and not is_natural_stop() then
            hold_quiet()
        end
        return
    end

    if consume_script_pause(value) then
        debug_log("Ignoring script pause write (" .. tostring(value) .. ")")
        return
    end

    if value == nil or not active_file then
        return
    end

    debug_log("External pause change: " .. (value and "pausing" or "unpausing"))

    if value then
        begin_fade("out")
    else
        begin_fade("in")
    end
end

local function on_volume_change(_, value)
    if not quiet_hold or value == nil or value <= 0.5 then
        return
    end
    -- The user moved the volume knob while we were holding silence.
    base_volume = value
    no_osd_set("volume", 0)
    debug_log(string.format("Volume adjusted while paused, target %.2f", value))
end

local function cleanup()
    debug_log("Cleanup")
    stop_timer()
    phase = nil
    restore_video()
    quiet_hold = false
    if base_volume ~= nil then
        no_osd_set("volume", base_volume)
    end
    level = 1
    held_soft = false
    anchor_pos = nil
    paused_pos = nil
    active_file = false
    reset_pause_ack()
end

local function on_file_loaded()
    reset_pause_ack()
    active_file = true
    if phase == nil then
        level = 1
        held_soft = false
        quiet_hold = false
    end
    debug_log("File loaded")
end

validate_options()

mp.add_forced_key_binding("space", "gradual_pause_space", handle_pause_key)
mp.add_forced_key_binding("p", "gradual_pause_p", handle_pause_key)

if mp.get_property("path") then
    active_file = true
end

mp.observe_property("pause", "bool", on_pause_change)
mp.observe_property("volume", "number", on_volume_change)
mp.register_event("end-file", cleanup)
mp.register_event("shutdown", cleanup)
mp.register_event("file-loaded", on_file_loaded)

debug_log("gradual_pause v" .. SCRIPT_VERSION .. " loaded")
