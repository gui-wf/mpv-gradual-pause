-- mpv-side checks for gradual_pause. Loaded after the script under test.
-- GP_CASE selects a scenario. GP_RESULT is the report path.

local mp = require "mp"

local case_name = os.getenv("GP_CASE") or "main"
local result_path = os.getenv("GP_RESULT") or "/tmp/gradual-pause-result.txt"
local lines = {}

local function report(kind, name, detail)
    local line = kind .. " " .. name
    if detail and detail ~= "" then
        line = line .. " — " .. detail
    end
    lines[#lines + 1] = line
    mp.msg.info(line)
end

local function finish()
    local f = io.open(result_path, "w")
    if f then
        f:write(table.concat(lines, "\n"), "\n")
        f:close()
    end
    mp.command("quit")
end

local samples = {}
local started = mp.get_time()

local function snap()
    samples[#samples + 1] = {
        t = mp.get_time() - started,
        vol = mp.get_property_number("volume"),
        pause = mp.get_property_bool("pause"),
        pos = mp.get_property_number("time-pos"),
        contrast = mp.get_property_number("contrast"),
        sharpen = mp.get_property_number("sharpen"),
    }
end

mp.observe_property("volume", "number", function()
    snap()
end)
mp.observe_property("pause", "bool", function()
    snap()
end)
mp.add_periodic_timer(0.02, snap)

local function latest()
    return samples[#samples]
end

local function wait_until(timeout, pred, cont)
    local elapsed = 0
    local timer
    timer = mp.add_periodic_timer(0.02, function()
        elapsed = elapsed + 0.02
        if pred() then
            timer:kill()
            cont(true)
        elseif elapsed >= timeout then
            timer:kill()
            cont(false)
        end
    end)
end

local function min_volume_between(t0, t1)
    local min_v = nil
    for _, s in ipairs(samples) do
        if s.t >= t0 and s.t <= t1 and s.vol then
            if not min_v or s.vol < min_v then
                min_v = s.vol
            end
        end
    end
    return min_v
end

local function run_main()
    local issue_t, issue_pos
    mp.register_event("file-loaded", function()
        mp.add_timeout(0.55, function()
            local vol = mp.get_property_number("volume")
            local early = min_volume_between(0, 0.5)
            if vol and vol > 75 and early and early > 75 then
                report("PASS", "startup-does-not-duck", string.format("min=%.2f", early))
            else
                report("FAIL", "startup-does-not-duck",
                    string.format("vol=%s early=%s", tostring(vol), tostring(early)))
            end

            issue_t = mp.get_time() - started
            issue_pos = mp.get_property_number("time-pos")
            mp.set_property_bool("pause", true)

            wait_until(2.0, function()
                return mp.get_property_bool("pause")
                    and (mp.get_property_number("volume") or 0) > 75
            end, function(ok)
                local max_drop = 0
                local prev_vol = nil
                local moved = false
                for _, s in ipairs(samples) do
                    if s.t >= issue_t and s.t <= issue_t + 0.20 and s.vol and not s.pause then
                        if prev_vol and s.vol < prev_vol - 0.05 then
                            local drop = prev_vol - s.vol
                            if drop > max_drop then
                                max_drop = drop
                            end
                            moved = true
                        end
                        if s.vol then
                            prev_vol = s.vol
                        end
                    end
                end
                if moved and max_drop < 8 then
                    report("PASS", "fade-out-starts-gently",
                        string.format("max step=%.2f", max_drop))
                else
                    report("FAIL", "fade-out-starts-gently",
                        string.format("moved=%s max step=%s", tostring(moved), tostring(max_drop)))
                end

                local paused_pos = mp.get_property_number("time-pos")
                if ok and issue_pos and paused_pos and paused_pos >= issue_pos - 0.08 then
                    report("PASS", "pause-does-not-rewind",
                        string.format("%.3f -> %.3f", issue_pos, paused_pos))
                else
                    report("FAIL", "pause-does-not-rewind",
                        string.format("%s -> %s ok=%s", tostring(issue_pos),
                            tostring(paused_pos), tostring(ok)))
                end

                local dipped = false
                for _, s in ipairs(samples) do
                    if s.t > issue_t and s.contrast and s.contrast < -1 then
                        dipped = true
                    end
                end
                local contrast_now = mp.get_property_number("contrast") or 0
                if dipped and math.abs(contrast_now) < 0.2 then
                    report("PASS", "video-eases-then-clears",
                        string.format("now=%.2f", contrast_now))
                else
                    report("FAIL", "video-eases-then-clears",
                        string.format("dipped=%s now=%.3f vo=%s",
                            tostring(dipped), contrast_now,
                            tostring(mp.get_property("current-vo"))))
                end

                local target = (paused_pos or 0) + 2.5
                mp.set_property_number("time-pos", target)
                wait_until(1.2, function()
                    local pos = mp.get_property_number("time-pos")
                    return pos and math.abs(pos - target) < 0.35
                end, function(seeked)
                    local pos_before = mp.get_property_number("time-pos")
                    mp.set_property_bool("pause", false)
                    mp.add_timeout(0.12, function()
                        local pos = mp.get_property_number("time-pos")
                        local vol = mp.get_property_number("volume") or 100
                        if seeked and pos and pos_before
                            and math.abs(pos - pos_before) < 0.5
                            and pos > (issue_pos or 0) + 1.5
                            and vol > 3 and vol < 45 then
                            report("PASS", "seek-survives-unpause",
                                string.format("pos=%.3f vol=%.2f", pos, vol))
                        else
                            report("FAIL", "seek-survives-unpause",
                                string.format("seeked=%s before=%s pos=%s vol=%s",
                                    tostring(seeked), tostring(pos_before),
                                    tostring(pos), tostring(vol)))
                        end
                        finish()
                    end)
                end)
            end)
        end)
    end)
    mp.add_timeout(8, function()
        report("FAIL", "main-timeout", "scenario did not finish")
        finish()
    end)
end

local function run_eof()
    local min_v = 100
    mp.observe_property("volume", "number", function(_, v)
        if v and v < min_v then
            min_v = v
        end
    end)
    mp.add_timeout(2.4, function()
        local eof = mp.get_property_bool("eof-reached")
        local paused = mp.get_property_bool("pause")
        if eof and paused and min_v > 75 then
            report("PASS", "eof-does-not-fade", string.format("min=%.2f", min_v))
        else
            report("FAIL", "eof-does-not-fade",
                string.format("eof=%s pause=%s min=%.2f",
                    tostring(eof), tostring(paused), min_v))
        end
        finish()
    end)
end

local function run_restore()
    mp.register_event("file-loaded", function()
        mp.add_timeout(0.45, function()
            local anchor = mp.get_property_number("time-pos")
            mp.set_property_bool("pause", true)
            wait_until(2.0, function()
                return mp.get_property_bool("pause")
                    and (mp.get_property_number("volume") or 0) > 75
            end, function(ok)
                local paused_at = mp.get_property_number("time-pos")
                mp.set_property_bool("pause", false)
                -- The opt-in seek is asynchronous. After a short wait, playback
                -- should be near the pre-fade timestamp rather than the paused one.
                mp.add_timeout(0.35, function()
                    local pos = mp.get_property_number("time-pos")
                    local from_anchor = pos and anchor and math.abs(pos - (anchor + 0.35))
                    local from_paused = pos and paused_at and math.abs(pos - (paused_at + 0.35))
                    if ok and from_anchor and from_paused
                        and paused_at > anchor + 0.2
                        and from_anchor + 0.15 < from_paused then
                        report("PASS", "restore-position",
                            string.format("anchor=%.3f paused=%.3f now=%.3f",
                                anchor, paused_at, pos))
                    else
                        report("FAIL", "restore-position",
                            string.format("ok=%s anchor=%s paused=%s now=%s",
                                tostring(ok), tostring(anchor),
                                tostring(paused_at), tostring(pos)))
                    end
                    finish()
                end)
            end)
        end)
    end)
    mp.add_timeout(6, function()
        report("FAIL", "restore-timeout", "scenario did not finish")
        finish()
    end)
end

local function run_key()
    mp.register_event("file-loaded", function()
        mp.add_timeout(0.4, function()
            local mark = mp.get_time() - started
            mp.commandv("keypress", "space")
            wait_until(2.0, function()
                return mp.get_property_bool("pause")
            end, function(ok)
                local saw_dip_while_playing = false
                for _, s in ipairs(samples) do
                    if s.t >= mark and s.pause == false and s.vol and s.vol < 70 then
                        saw_dip_while_playing = true
                    end
                end
                if ok and saw_dip_while_playing then
                    report("PASS", "space-fades-before-pause", "")
                else
                    report("FAIL", "space-fades-before-pause",
                        string.format("paused=%s dipped=%s",
                            tostring(ok), tostring(saw_dip_while_playing)))
                end
                finish()
            end)
        end)
    end)
    mp.add_timeout(6, function()
        report("FAIL", "key-timeout", "scenario did not finish")
        finish()
    end)
end

if case_name == "eof" then
    run_eof()
elseif case_name == "restore" then
    run_restore()
elseif case_name == "key" then
    run_key()
else
    run_main()
end

-- Keep a reference so the periodic sampler is not collected.
latest()
