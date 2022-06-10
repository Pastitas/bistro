-- bistro
-- "press cafe" remake
-- by: @cfd90
-- originally by: @stretta

--engine.name = "KarplusRings"
engine.name = "PolyPerc"


local MusicUtil = require "musicutil"
local rings = include("we/lib/karplus_rings")
local hs = include("lib/halfsecond")
local midi_lib = include("lib/midi_lib")

local g
local clk

local white_piano_row
local white_piano_start
local black_piano_row
local black_piano_start
local octave_row

local pages = {"PLAY", "PATTERNS", "LENGTHS", "NOTES"}
local note_name = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local page = 1

local tracks = {}

function init()
  g = grid.connect()
  g.key = grid_key
  
  params:add_separator()
  params:add_option("clock_rate", "clock rate", {1, 2, 4, 8, 16}, 4)
  params:add_group("note data", 2 + g.cols)
  --OLD
  --params:add_number("base_note", "base note", 1, 127, 48)
  params:add_option("base_note_name", "base note name", note_name, 1)
  params:add_number("base_octave", "base note octave", -1, 8, 4)
  
  white_piano_row = (g.rows/2) + 1
  black_piano_row = (g.rows/2)
  white_piano_start = (g.cols/2) - 3
  black_piano_start = (g.cols/2) - 2
  octave_row = (g.rows/2)+1
  if g.cols <= 8 then
    octave_row = octave_row-1
  end
    
  local base_note = 48
  local start_notes = {0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24, 26}

  for i=1,g.cols do
    local note_name = "note_" .. i

    params:add_number(note_name, note_name:gsub("_", " "), -24, 48, start_notes[i])
    tracks[i] = { counter = nil, pattern = nil ,  active_note = nil}
  end
  
  params:add_group("pattern data", g.rows + (g.rows * g.cols))
  
  for i=1,g.rows do
    local pattern_len_name = "pattern_" .. i .. "_length"

    params:add_number(pattern_len_name, pattern_len_name:gsub("_", " "), 1, g.cols, math.min(g.rows, g.cols))
    params:set_action(pattern_len_name, function(x)
      grid_dirty = true
    end)
    
    for j=1,g.cols do
      local trig_name = "pattern_" .. i .. "_trig_" .. j
      
      params:add_number(trig_name, trig_name:gsub("_", " "), 0, 1, math.random() > 0.5 and 1 or 0)
      params:set_action(trig_name, function(x)
        grid_dirty = true
      end)
    end
  end
  
  params:add_separator()
  rings.params()
  
  params:add_separator()
  hs.init()
  
  midi_lib.init()
  
  params:bang()
  
  -- Overrides.
  params:set("damping", 3)
  params:set("brightness", 0.8)
  params:set("lpf_freq", 5000)
  params:set("lpf_gain", 1)
  params:set("bpf_freq", 200)
  params:set("bpf_res", 2)
  
  params:read()
  
  clk = clock.run(tick)
  hardware_clk = clock.run(function()
    while true do
      clock.sleep(1/30)
      if grid_dirty then
        grid_redraw()
        grid_dirty = false
      end
      if screen_dirty then
        redraw()
        screen_dirty = false
      end
    end
  end
  )
  
  grid_dirty = true
end

function cleanup()
  params:write()
end

function tick()
  while true do
    local rate = params:get("clock_rate")
    clock.sync(1/rate)
    
    grid_dirty = true
    
    screen_dirty = true
    
    for i=1,g.cols do
      local track = tracks[i]
      
      if track.pattern ~= nil and track.counter ~= nil then
        -- Play if trigged.
        local p = get_pattern(track.pattern)
        
        if p[track.counter] == 1 then
          local note = get_note(i)
          local freq = MusicUtil.note_num_to_freq(note)

          engine.hz(freq)
          
          track.active_note = note
          midi_out:note_on(track.active_note, params:get("MIDI_out_velocity"), params:get("MIDI_out_channel"))
          
        else
          midi_out:note_off(track.active_note, params:get("MIDI_out_velocity"), params:get("MIDI_out_channel"))
        end
        
        -- Advance counter.
        local length = get_pattern_length(track.pattern)
        
        track.counter = track.counter + 1
        
        if track.counter > length then
          track.counter = 1
        end
      end
    end
  end
end

function get_base_octave()
  return params:get("base_octave")
end
function set_base_octave(o)
  return params:set("base_octave", o)
end
function get_base_note()
  return params:get("base_note_name") + ((params:get("base_octave") + 1) * 12 )
end
function set_base_note(i)
  return params:set("base_note_name", i)
end
function get_base_note_name()
  return note_name[params:get("base_note_name")]..tostring(params:get("base_octave"))
end
function get_note_col(i)
  return params:get("note_" .. i)
end
function set_note_col(i, v)
  params:set("note_" .. i, v)
end
function get_note(i)
  --OLD
  --return params:get("note_" .. i) + params:get("base_note")
  return params:get("note_" .. i) + get_base_note()
end

function get_pattern_length(i)
  return params:get("pattern_" .. i .. "_length")
end

function set_pattern_length(i, n)
  return params:set("pattern_" .. i .. "_length", n)
end

function set_pattern_trig(i, j, t)
  params:set("pattern_" .. i .. "_trig_" .. j, t)
end

function get_pattern(i)
  local p = {}
  
  for j=1,get_pattern_length(i) do
    table.insert(p, params:get("pattern_" .. i .. "_trig_" .. j))
  end
  
  return p
end

function grid_key(x, y, z)
  if page == 1 then
    -- PLAY
    if z == 1 and tracks[x].counter == nil then
      tracks[x].pattern = y
      tracks[x].counter = 1
    elseif z == 0 then
      tracks[x].pattern = nil
      tracks[x].counter = nil
      midi_out:note_off(tracks[x].active_note)
    end
  elseif page == 2 then
    -- PATTERNS
    if z == 1 then
      local p = get_pattern(y)
      local t = p[x]
      
      set_pattern_trig(y, x, t == 1 and 0 or 1)
    end
  elseif page == 3 then
    -- LENGTH
    if z == 1 then
      set_pattern_length(y, x)
    end
  elseif page == 4 then
    -- NOTE 
    if z == 1 and y == 1 then
      note = get_note_col(x)
      set_note_col(x, note+5)
    elseif z == 1 and y == 2 then
      note = get_note_col(x)
      set_note_col(x, note+1)
    elseif z == 1 and y == g.rows then
      note = get_note_col(x)
      set_note_col(x, note-5)
    elseif z == 1 and y == g.rows-1 then
      note = get_note_col(x)
      set_note_col(x, note-1)
    elseif z == 1 and y == white_piano_row then
      if x == white_piano_start then
        set_base_note(1)
      elseif x == (white_piano_start + 1) then
        set_base_note(3)
      elseif x == (white_piano_start + 2) then
        set_base_note(5)
      elseif x == (white_piano_start + 3) then
        set_base_note(6)
      elseif x == (white_piano_start + 4) then
        set_base_note(8)
      elseif x == (white_piano_start + 5) then
        set_base_note(10)
      elseif x == (white_piano_start + 6) then
        set_base_note(12)
      end
      if octave_row == white_piano_row then
        if x == 3 then
          octave = get_base_octave()
          set_base_octave(octave - 1)
        elseif x == g.cols-2 then
          octave = get_base_octave()
          set_base_octave(octave + 1)
        end
      end
    elseif z ==1 and y == octave_row then
      if x == 3 then
        octave = get_base_octave()
        set_base_octave(octave - 1)
      elseif x == g.cols-2 then
        octave = get_base_octave()
        set_base_octave(octave + 1)
      end
    elseif z == 1 and y == black_piano_row then
      if x == black_piano_start then
        set_base_note(2)
      elseif x == (black_piano_start + 1) then
        set_base_note(4)
      elseif x == (black_piano_start + 2) then
        set_base_note(7)
      elseif x == (black_piano_start + 3) then
        set_base_note(9)
      elseif x == (black_piano_start + 4) then
        set_base_note(11)
      end
    end
  end
end

function grid_redraw()
  g:all(0)
  
  if page == 1 then
    -- PLAY
    for i=1,g.cols do
      local track = tracks[i]
      
      if track.pattern ~= nil and track.counter ~= nil then
        local pattern = get_pattern(track.pattern)
        local length = get_pattern_length(track.pattern)
        local c = track.counter
        
        if track.counter ~= nil then
          local ti = c
          
          for j=1,g.rows do
            ti = ti + 1
            
            if ti > length then
              ti = 1
            end
            
            local trig = pattern[ti]
            g:led(i, g.rows - j + 1, trig == 1 and 15 or 0)
          end
        end
      end
    end
  elseif page == 2 then
    -- PATTERNS
    for i=1,g.rows do
      local p = get_pattern(i)
      
      for j=1,g.cols do
        local trig = p[j]
        g:led(j, i, trig == 1 and 15 or 0)
      end
    end
  elseif page == 3 then
    -- LENGTHS
    for i=1,g.rows do
      local length = get_pattern_length(i)
      
      for j=1,length do
        g:led(j, i, 15)
      end
    end
  elseif page == 4 then
    -- NOTES
    -- Choosing inteval for col
    for i=1,g.cols do
      g:led(i,1,15)
      g:led(i,2,8)
      g:led(i,g.rows-1,8)
      g:led(i,g.rows,15)
    end
    
    -- piano roll for choosing note
    for i=0,4 do
     g:led(black_piano_start+i,black_piano_row, 10)
    end
    for i=0,6 do
     g:led(white_piano_start+i,white_piano_row, 10)
    end
    
    --  octave buttons
    g:led(3, octave_row, 15)
    g:led(g.cols-2, octave_row, 15)

    
  end
  g:refresh()
end

function enc(n, d)
  if n == 1 then
    page = util.clamp(page + d, 1, #pages)
    
    for i=1,g.cols do
      tracks[i] = { counter = nil, pattern = nil }
    end
  end
  
  if page == 1 then
    -- PLAY
    if n == 2 then
      params:delta("cutoff", d)
    elseif n == 3 then
      params:delta("pw", d)
    end
  end
  
  grid_dirty = true
  screen_dirty = true
end

function key(n, z)
  if z == 0 then
    return
  end
  
  if page == 1 then
    -- PLAY
    -- todo: random notes?
  elseif page == 2 then
    -- PATTERNS
    if n == 3 then
      for i=1,g.cols do
        for j=1,g.rows do
          set_pattern_trig(i, j, math.random() > 0.5 and 1 or 0)
        end
      end
    end
  elseif page == 3 then
    -- LENGTH
    if n == 3 then
      for i=1,g.cols do
        set_pattern_length(i, math.random(1, g.cols))
      end
    end
  elseif page == 4 then
    -- NOTE
    if n == 3 then
      for i=1,g.cols do
        set_note_col(i, 0) -- math.random(-24, 48))
      end
    end
  end
end

function redraw()
  screen.clear()
  
  screen.move(0, 10)
  screen.level(15)
  screen.text(pages[page])
  
  if page == 1 then
    -- PLAY
    for i=1,g.cols do
      local track = tracks[i]
      
      screen.move(10 + (i-1)*10, 36)
      
      if track.pattern ~= nil and track.counter ~= nil then
        local p = get_pattern(track.pattern)
        local t = p[track.counter]
        
        screen.level(t == 1 and 15 or 1)
        screen.text(t == 1 and "." or ".")
      else
        screen.level(1)
        screen.text(".")
      end
    end
  elseif page == 2 then
    -- PATTERNS
    --screen.move(10, 36)
    screen.move(10, 46)
    screen.level(15)
    screen.text("KEY3")
    screen.level(5)
    screen.text(" to randomize")
  elseif page == 3 then
    -- LENGTHS
    for i=1, g.rows do
      local length = get_pattern_length(i)
      
      screen.move(10 + (i-1)*10, 36)
      screen.level(length)
      screen.text(length)
    end
    
    screen.move(10, 46)
    screen.level(15)
    screen.text("KEY3")
    screen.level(5)
    screen.text(" to randomize")
  elseif page == 4 then
    -- NOTES
    screen.move(50,10)
    screen.level(5)
    screen.text("Base note: ")
    screen.level(15)
    screen.text(get_base_note_name())
    
    for i=1, g.cols do
      local note = get_note_col(i)
      h_spacing = 3 + (i-1)*7.5
      if (i % 2 == 0) then
        screen.move(h_spacing, 38)
      else
        screen.move(h_spacing, 30)
      end
      --screen.level(note)
      screen.text(note)
    end
    
    --screen.move(15, 58)
    screen.move(10, 46)
    screen.level(15)
    screen.text("KEY3")
    screen.level(5)
    screen.text(" to reset to 0")
  
end
  
  screen.update()
end
