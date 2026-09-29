#!/usr/bin/env lua5.4
-- Behavioral tests for gradual_pause.lua with a stub mpv runtime.
-- Run from the repo root: lua5.4 tests/run_unit.lua

local fails = 0

local function check(name, cond, detail)
    if cond then
        io.write("PASS ", name, "\n")
    else
        fails = fails + 1
        io.write("FAIL ", name)
        if detail then
            io.write(" — ", detail)
        end
        io.write("\n")
    end
end

local function near(a, b, eps)
    return a ~= nil and b ~= nil and math.abs(a - b) <= eps
end

local function load_script(overrides)
    local props = {
        volume = 80,
        pause = false,
        ["time-pos"] = 10,
        ["eof-reached"] = false,
        ["idle-active"] = false,
        seeking = false,
        path = "/tmp/media.mp4",
        ["current-vo"] = "gpu",
        ["current-tracks/video"] = { id = 1 },
        contrast = 0,
        saturation = 0,
        brightness = 0,
        sharpen = 0,
        ["video-params/w"] = 320,
    }
    local observers = {}
    local keys = {}
    local events = {}
    local warnings = {}
    local now = 0
    local timer = nil
    local delivery = "sync"
    if overrides and overrides.__delivery then
        delivery = overrides.__delivery
        overrides.__delivery = nil
    end
    local last_notified_pause = props.pause
    local pause_note = nil
    local pause_note_valid = false
    local timeouts = {}

    local function fire(name, value)
        for _, ob in ipairs(observers) do
            if ob.name == name then
                ob.fn(name, value)
            end
        end
    end

    local mp = {}

    function mp.get_property(name)
        local value = props[name]
        if value == nil then
            return nil
        end
        if type(value) == "boolean" then
            return value and "yes" or "no"
        end
        if type(value) == "table" then
            return nil
        end
        return tostring(value)
    end

    function mp.get_property_number(name)
        local value = props[name]
        if type(value) == "number" then
            return value
        end
        return nil
    end

    function mp.get_property_bool(name)
        local value = props[name]
        if value == nil then
            return nil
        end
        return not not value
    end

    function mp.get_property_native(name)
        return props[name]
    end

    function mp.get_time()
        return now
    end

    local function run_timeouts()
        local guard = 0
        while guard < 30 do
            guard = guard + 1
            local ran = false
            local i = 1
            while i <= #timeouts do
                if timeouts[i].t <= now + 1e-9 then
                    local fn = timeouts[i].fn
                    table.remove(timeouts, i)
                    fn()
                    ran = true
                else
                    i = i + 1
                end
            end
            if not ran then
                break
            end
        end
    end

    local function deliver_pause()
        if not pause_note_valid then
            return
        end
        local note = pause_note
        pause_note_valid = false
        if note == last_notified_pause then
            return
        end
        last_notified_pause = note
        fire("pause", note)
    end

    function mp.set_property_bool(name, value)
        if name == "pause" and props._repause and value == false then
            -- keep-open (or similar) puts pause back before mpv notifies.
            props.pause = true
            if delivery == "async" then
                if last_notified_pause == true then
                    pause_note_valid = false
                else
                    pause_note = true
                    pause_note_valid = true
                end
            end
            return
        end
        props[name] = value
        if name ~= "pause" then
            return
        end
        if delivery == "async" then
            if value == last_notified_pause then
                pause_note_valid = false
            else
                pause_note = value
                pause_note_valid = true
            end
            return
        end
        if value ~= last_notified_pause then
            last_notified_pause = value
            fire("pause", value)
        end
    end

    function mp.add_timeout(seconds, fn)
        local handle = { t = now + seconds, fn = fn, alive = true }
        timeouts[#timeouts + 1] = handle
        function handle:kill()
            self.alive = false
            self.fn = function() end
        end
        return handle
    end

    function mp.set_property_number(name, value)
        props[name] = value
    end

    function mp.set_property(name, value)
        props[name] = tonumber(value) or value
    end

    function mp.commandv(...)
        local args = { ... }
        if args[1] == "no-osd" and args[2] == "set" then
            props[args[3]] = tonumber(args[4]) or args[4]
            return true
        end
        return nil, "unknown command"
    end

    function mp.observe_property(name, _, fn)
        observers[#observers + 1] = { name = name, fn = fn }
        local value = props[name]
        if type(value) == "boolean" or value == nil then
            fn(name, value)
        end
    end

    function mp.add_forced_key_binding(key, _, fn)
        keys[key] = fn
    end

    function mp.register_event(name, fn)
        events[name] = fn
    end

    function mp.add_periodic_timer(interval, fn)
        local handle = { interval = interval, alive = true, fn = fn }
        function handle:kill()
            self.alive = false
        end
        timer = handle
        return handle
    end

    local function advance(dt)
        local left = dt
        local guard = 0
        while left > 1e-6 and guard < 10000 do
            guard = guard + 1
            local step = left
            if timer and timer.alive then
                step = math.min(left, timer.interval)
            end
            now = now + step
            if not props.pause then
                props["time-pos"] = (props["time-pos"] or 0) + step
            end
            left = left - step
            if timer and timer.alive then
                timer.fn()
            end
            run_timeouts()
        end
    end

    -- Returns the volume audible at the moment pause changes, before the
    -- script observer runs when delivery is async.
    local function user_pause(value)
        local audible = props.volume
        props.pause = value and true or false
        if delivery == "async" then
            if props.pause == last_notified_pause then
                pause_note_valid = false
            else
                pause_note = props.pause
                pause_note_valid = true
            end
        else
            if props.pause ~= last_notified_pause then
                last_notified_pause = props.pause
                fire("pause", props.pause)
            end
            run_timeouts()
        end
        return audible
    end

    local function flush()
        deliver_pause()
        run_timeouts()
    end

    package.loaded["mp"] = mp
    package.preload["mp"] = function()
        return mp
    end
    package.loaded["mp.options"] = nil
    package.preload["mp.options"] = function()
        return {
            read_options = function(target)
                for key, value in pairs(overrides or {}) do
                    target[key] = value
                end
            end,
        }
    end
    package.loaded["mp.msg"] = nil
    package.preload["mp.msg"] = function()
        return {
            info = function() end,
            warn = function(text)
                warnings[#warnings + 1] = text
            end,
        }
    end

    dofile("scripts/gradual_pause.lua")

    return {
        props = props,
        keys = keys,
        events = events,
        warnings = warnings,
        advance = advance,
        user_pause = user_pause,
        flush = flush,
        timer = function()
            return timer
        end,
    }
end

local function test_startup_does_not_duck()
    local rt = load_script()
    check("startup leaves volume alone", rt.props.volume == 80, tostring(rt.props.volume))
    rt.advance(0.35)
    check("startup stays at full volume", rt.props.volume == 80, tostring(rt.props.volume))
    check("startup is not paused", rt.props.pause == false)
end

local function test_fade_out_is_gentle_and_monotonic()
    local rt = load_script()
    rt.keys.space()
    local previous = rt.props.volume
    local monotonic = true
    local max_step = 0
    rt.advance(0.02)
    local first = previous - rt.props.volume
    check("fade-out first tick is a small step", first > 0 and first < 6, tostring(first))
    local guard = 0
    while not rt.props.pause and guard < 100 do
        guard = guard + 1
        local before = rt.props.volume
        rt.advance(0.02)
        if not rt.props.pause then
            local drop = before - rt.props.volume
            if drop > max_step then
                max_step = drop
            end
            if rt.props.volume > previous + 0.05 then
                monotonic = false
            end
            previous = rt.props.volume
        end
    end
    check("fade-out steps stay fine", max_step < 8, tostring(max_step))
    check("fade-out volume is monotonic", monotonic)
    check("fade-out ends paused", rt.props.pause == true)
    check("paused volume stays silent", near(rt.props.volume, 0, 0.05), tostring(rt.props.volume))
    check("settled pause is a clear frame", near(rt.props.contrast, 0, 0.05)
        and near(rt.props.sharpen, 0, 0.05))
end

local function test_coarse_steps_still_sample_finely()
    local rt = load_script({ steps = 1 })
    rt.keys.space()
    rt.advance(0.04)
    check("steps=1 still moves within 40ms", rt.props.volume < 78 and rt.props.volume > 60,
        tostring(rt.props.volume))
    check("steps=1 timer is at most 20ms", rt.timer() and rt.timer().interval <= 0.0201,
        rt.timer() and tostring(rt.timer().interval) or "nil")
end

local function test_video_pulse_on_gpu()
    local rt = load_script()
    rt.keys.space()
    rt.advance(0.22)
    check("mid-fade contrast dips", rt.props.contrast < -4, tostring(rt.props.contrast))
    check("mid-fade sharpen blurs on gpu", rt.props.sharpen < -10, tostring(rt.props.sharpen))
    rt.advance(0.4)
    check("picture restored after pause", near(rt.props.contrast, 0, 0.05)
        and near(rt.props.sharpen, 0, 0.05))
end

local function test_video_hold()
    local rt = load_script({ video_hold = true })
    rt.keys.space()
    rt.advance(0.6)
    check("held pause keeps the dim", rt.props.contrast < -4, tostring(rt.props.contrast))
    rt.keys.space()
    rt.advance(0.6)
    check("unpause clears a held dim", near(rt.props.contrast, 0, 0.05),
        tostring(rt.props.contrast))
end

local function test_seek_while_paused_survives()
    local rt = load_script()
    rt.keys.space()
    rt.advance(0.6)
    local paused_at = rt.props["time-pos"]
    rt.props["time-pos"] = paused_at + 5
    rt.keys.space()
    check("unpause does not rewind a seek", near(rt.props["time-pos"], paused_at + 5, 0.02),
        tostring(rt.props["time-pos"]))
    rt.advance(0.04)
    check("fade-in is underway but not snapped open",
        rt.props.volume > 5 and rt.props.volume < 40, tostring(rt.props.volume))
    rt.advance(0.7)
    check("fade-in restores volume", near(rt.props.volume, 80, 0.05), tostring(rt.props.volume))
    check("fade-in ends playing", rt.props.pause == false)
end

local function test_restore_position_opt_in()
    local rt = load_script({ restore_position = true })
    local start = rt.props["time-pos"]
    rt.keys.space()
    rt.advance(0.6)
    local paused_at = rt.props["time-pos"]
    check("playback advanced during fade-out", paused_at > start + 0.2,
        tostring(paused_at))
    rt.keys.space()
    check("opt-in restore returns to the fade start", near(rt.props["time-pos"], start, 0.05),
        tostring(rt.props["time-pos"]))

    local rt2 = load_script({ restore_position = true })
    rt2.keys.space()
    rt2.advance(0.6)
    local paused2 = rt2.props["time-pos"]
    rt2.props["time-pos"] = paused2 + 4
    rt2.keys.space()
    check("opt-in restore still yields to a seek", near(rt2.props["time-pos"], paused2 + 4, 0.02),
        tostring(rt2.props["time-pos"]))
end

local function test_eof_pause_is_ignored()
    local rt = load_script()
    rt.props["eof-reached"] = true
    rt.user_pause(true)
    check("eof pause stays paused", rt.props.pause == true)
    check("eof pause does not duck volume", rt.props.volume == 80, tostring(rt.props.volume))
    rt.advance(0.3)
    check("eof pause does not start a ramp", rt.props.volume == 80)
end

local function test_eof_key_toggles_without_fade()
    local rt = load_script()
    rt.props["eof-reached"] = true
    rt.props.pause = true
    rt.keys.space()
    check("eof key unpauses immediately", rt.props.pause == false)
    check("eof key does not zero volume", rt.props.volume == 80, tostring(rt.props.volume))
    rt.advance(0.2)
    check("eof key does not fade in", rt.props.volume == 80, tostring(rt.props.volume))
end

local function test_reverse_and_external_pause()
    local rt = load_script()
    rt.keys.space()
    rt.advance(0.15)
    rt.keys.space()
    rt.advance(0.6)
    check("reversing a fade-out resumes", rt.props.pause == false)
    check("reversed fade returns to full volume", near(rt.props.volume, 80, 0.05),
        tostring(rt.props.volume))

    rt.keys.space()
    rt.advance(0.6)
    rt.keys.space()
    rt.advance(0.12)
    local pos = rt.props["time-pos"]
    rt.user_pause(true)
    rt.advance(0.6)
    check("external pause during fade-in ends paused", rt.props.pause == true)
    check("external pause does not keep playing", near(rt.props["time-pos"], pos, 0.02),
        tostring(rt.props["time-pos"]))
    check("external pause holds silence", near(rt.props.volume, 0, 0.05),
        tostring(rt.props.volume))
end

local function test_second_cycle_not_swallowed()
    local rt = load_script()
    rt.keys.space()
    rt.advance(0.6)
    rt.keys.space()
    rt.advance(0.6)
    local pos = rt.props["time-pos"]
    rt.user_pause(true)
    rt.advance(0.6)
    check("later external pause is not swallowed", rt.props.pause == true)
    check("later external pause does not play through",
        near(rt.props["time-pos"], pos, 0.02) and near(rt.props.volume, 0, 0.05),
        string.format("pos=%s vol=%s", tostring(rt.props["time-pos"]), tostring(rt.props.volume)))
    local heard = rt.user_pause(false)
    check("later unpause was already silent", heard ~= nil and heard < 1, tostring(heard))
    rt.advance(0.08)
    check("later unpause fades instead of snapping open",
        rt.props.pause == false and rt.props.volume > 1 and rt.props.volume < 50,
        tostring(rt.props.volume))
end

local function test_cleanup_restores_picture()
    local rt = load_script()
    rt.keys.space()
    rt.advance(0.2)
    check("cleanup precondition: picture is eased", rt.props.contrast < -1,
        tostring(rt.props.contrast))
    rt.events["end-file"]()
    check("end-file restores contrast", near(rt.props.contrast, 0, 0.05),
        tostring(rt.props.contrast))
    check("end-file restores volume", near(rt.props.volume, 80, 0.05), tostring(rt.props.volume))
end

local function test_curves_and_validation()
    local linear = load_script({ fade_curve = "linear" })
    linear.keys.space()
    linear.advance(0.04)
    check("linear ramp is a steady slider move", linear.props.volume < 76
        and linear.props.volume > 68, tostring(linear.props.volume))

    local bad = load_script({
        fade_out_duration = 9,
        fade_curve = "nope",
        video_transition = "sparkle",
    })
    check("invalid duration is clamped", bad.props.volume == 80)
    local saw = false
    for _, text in ipairs(bad.warnings) do
        if text:find("fade_out_duration", 1, true) then
            saw = true
        end
    end
    check("invalid options warn", saw)
end

local function test_blur_fallback()
    local rt = load_script({
        video_transition = "blur",
        ["ignored"] = true,
    })
    -- current-vo is applied by the mock default; override after load is too late.
    -- Reload with gpu disabled by patching props before the fade, which is what
    -- capture_video reads.
    rt.props["current-vo"] = "null"
    rt.keys.space()
    rt.advance(0.22)
    check("non-gpu blur falls back to a dim", rt.props.saturation < -4,
        tostring(rt.props.saturation))
    check("non-gpu blur does not invent sharpen", near(rt.props.sharpen, 0, 0.05),
        tostring(rt.props.sharpen))
end

local function test_gpu_next_does_not_blur()
    local rt = load_script()
    rt.props["current-vo"] = "gpu-next"
    rt.props.sharpen = 0
    rt.keys.space()
    rt.advance(0.22)
    check("gpu-next does not write sharpen", near(rt.props.sharpen, 0, 0.05),
        tostring(rt.props.sharpen))
    check("gpu-next still dims", rt.props.contrast < -4, tostring(rt.props.contrast))
end

local function test_async_external_unpause_is_silent()
    local rt = load_script({ __delivery = "async", fade_out_duration = 0 })
    local pos = rt.props["time-pos"]
    rt.user_pause(true)
    rt.flush()
    check("zero-duration external pause stays paused", rt.props.pause == true)
    check("zero-duration external pause is silent", near(rt.props.volume, 0, 0.05),
        tostring(rt.props.volume))
    rt.advance(0.35)
    check("zero-duration external pause does not play through",
        near(rt.props["time-pos"], pos, 0.001), tostring(rt.props["time-pos"]))

    local heard = rt.user_pause(false)
    check("async unpause hears silence before the observer", heard < 1, tostring(heard))
    rt.flush()
    check("first fade-in sample is not full volume", rt.props.volume < 5,
        tostring(rt.props.volume))
    rt.advance(0.08)
    check("async unpause then ramps", rt.props.volume > 1 and rt.props.volume < 55,
        tostring(rt.props.volume))

    local pos2 = rt.props["time-pos"]
    rt.user_pause(true)
    rt.flush()
    rt.advance(0.3)
    check("second external pause is not swallowed",
        rt.props.pause == true and near(rt.props["time-pos"], pos2, 0.02),
        string.format("pause=%s pos=%s", tostring(rt.props.pause),
            tostring(rt.props["time-pos"])))
end

local function test_coalesced_eof_toggle_does_not_stick()
    local rt = load_script({ __delivery = "async" })
    rt.props["eof-reached"] = true
    rt.user_pause(true)
    rt.flush()
    rt.props._repause = true
    rt.keys.space()
    rt.flush()
    check("coalesced eof toggle stays paused", rt.props.pause == true)
    rt.props["eof-reached"] = false
    rt.props._repause = false
    rt.user_pause(false)
    rt.flush()
    rt.advance(0.08)
    check("pause ack does not swallow the next unpause",
        rt.props.pause == false and rt.props.volume < 55,
        string.format("pause=%s vol=%s", tostring(rt.props.pause),
            tostring(rt.props.volume)))
end

test_startup_does_not_duck()
test_fade_out_is_gentle_and_monotonic()
test_coarse_steps_still_sample_finely()
test_video_pulse_on_gpu()
test_video_hold()
test_seek_while_paused_survives()
test_restore_position_opt_in()
test_eof_pause_is_ignored()
test_eof_key_toggles_without_fade()
test_reverse_and_external_pause()
test_second_cycle_not_swallowed()
test_cleanup_restores_picture()
test_curves_and_validation()
test_blur_fallback()
test_gpu_next_does_not_blur()
test_async_external_unpause_is_silent()
test_coalesced_eof_toggle_does_not_stick()

if fails > 0 then
    io.write(fails, " failed\n")
    os.exit(1)
end
io.write("all unit tests passed\n")
