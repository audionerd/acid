-- acid
--
-- tb-303-style sequencer
-- for crow + x0x-heart + grid
--

-- influenced by Julian Schmidt’s “analysis of the µpd650c-133 cpu timing”
-- http://sonic-potions.com/Documentation/Analysis_of_the_D650C-133_CPU_timing.pdf
--
-- designed for use with the open source x0x-heart + pacemaker
-- http://openmusiclabs.com/projects/x0x-heart

local s = require 'sequins'
local fileselect = require 'fileselect'
local textentry = require 'textentry'

local g = grid.connect()

local function wrap_index(s, ix) return ((ix - 1) % s.length) + 1 end

-- via http://lua-users.org/wiki/CopyTable
local function deepcopy(orig, copies)
  copies = copies or {}
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
      if copies[orig] then
          copy = copies[orig]
      else
          copy = {}
          copies[orig] = copy
          for orig_key, orig_value in next, orig, nil do
              copy[deepcopy(orig_key, copies)] = deepcopy(orig_value, copies)
          end
          setmetatable(copy, deepcopy(getmetatable(orig), copies))
      end
  else -- number, string, boolean, etc
      copy = orig
  end
  return copy
end

-- save/load
local function get_pattern_table(src)
  local t = {}
  for i = 1,16 do
    t[i] = {
      src.note[i],
      src.octave[i],
      src.gate[i],
      src.accent[i],
      src.slide[i]
    }
  end
  return t
end

local function serialize_pattern()
  return {
    length = context.length,

    loop = deepcopy(context.loop),

    note = context.note,
    gate = context.gate,
    accent = context.accent,
    slide = context.slide,
    octave = context.octave
  }
end

local function deserialize_pattern(src, dst)
  dst.length = src.length

  dst.loop:settable(src.loop.data)

  dst.note = src.note
  dst.gate = src.gate
  dst.accent = src.accent
  dst.slide = src.slide
  dst.octave = src.octave

  context.pattern:settable(get_pattern_table(context))
end

local pattern_folder_path = norns.state.data .. "patterns/"

function pattern_load()
  fileselect.enter(pattern_folder_path, function(srcpath)
    if srcpath ~= 'cancel' then
      local data = tab.load(srcpath)
      if data ~= nil then
        deserialize_pattern(data, context)

        context.loop:select(1)
        context.pattern:select(1)
      end
    end
  end)
end

local function pattern_save()
  textentry.enter(function(input)
    if input then
      if util.file_exists(pattern_folder_path) == nil then
        util.make_dir(pattern_folder_path)
      end

      local dst = pattern_folder_path .. input .. ".acd"

      if util.file_exists(dst) then
        -- TODO show error message
      else
        tab.save(serialize_pattern(), dst)
      end
    end
  end)
end
local function pattern_overwrite()
  fileselect.enter(pattern_folder_path, function(srcpath)
    if srcpath ~= 'cancel' then
      tab.save(serialize_pattern(), srcpath)
    end
  end)
end
local function pattern_remove()
  fileselect.enter(pattern_folder_path, function(srcpath)
    if srcpath ~= 'cancel' then
      local data = tab.load(srcpath)
      if data ~= nil then
        os.execute("rm "..srcpath)
      end
    end
  end)
end

context = {
  -- 6 clock pulses per step
  pulse   = s{1,2,3,4,5,6},

  -- 16-step pattern pattern playback
  length  = 16,

  -- loop range
  loop   = s{1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16},

  -- pattern data
  note    = { 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0 },,
  gate    = { 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0 },
  accent  = { 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0 },
  slide   = { 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0 },
  octave  = { 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0 },

  -- pattern sequins
  pattern = s{},

  -- current step
  currstep = 1,

  -- editing
  cursor = 1,

  -- loop start
  loop_start = nil,
  loop_pending = nil,

  -- playback
  running = false
}

local function crow_send_cv(volts)
  crow.output[1].volts = volts
end
local function crow_send_gate_on()
  crow.output[2].volts = 5
end
local function crow_send_gate_off()
  crow.output[2].volts = 0
end
local function crow_send_accent_on()
  crow.output[3].volts = 5
end
local function crow_send_accent_off()
  crow.output[3].volts = 0
end
local function crow_send_slide_on()
  crow.output[4].volts = 5
end
local function crow_send_slide_off()
  crow.output[4].volts = 0
end

local send_cv = crow_send_cv
local send_gate_on = crow_send_gate_on
local send_gate_off = crow_send_gate_off
local send_accent_on = crow_send_accent_on
local send_accent_off = crow_send_accent_off
local send_slide_on = crow_send_slide_on
local send_slide_off = crow_send_slide_off

local function send_transport_rewind_and_start()
  context.loop:select(1)
  context.pattern:select(1)
  context.running = true
end
local function send_transport_pause()
  context.running = false
  send_gate_off()
end
local function send_transport_continue()
  context.running = true
end



local function update_loop_pending()
  context.loop:settable(context.loop_pending)
  context.loop_pending = nil

  context.loop:select(1)
  context.pattern:select(1)
end

local function on_pulse()
  if not context.running then
    if context.loop_pending ~= nil then
      update_loop_pending()
    end
    return
  end

  pulse = context.pulse()

  if pulse == 1 then
    if context.loop_pending ~= nil then
      update_loop_pending()
    end

    context.currstep = context.loop()
    context.pattern:select(context.currstep)
    local note, octave, gate, accent, slide = table.unpack(context.pattern())

    send_cv(
      (24 + (note + (octave * 12))) / 12
    )

    if gate == 1 then
      send_gate_on()
    end

    if accent == 1 then
      send_accent_on()
    else
      send_accent_off()
    end

    if slide == 1 then
      send_slide_on()
    else
      send_slide_off()
    end
  end

  if pulse == 4 then
    local nextvalues = context.pattern[wrap_index(context.pattern, context.pattern.ix + 1)]
    local nextnote, nextoctave, nextgate, nextaccent, nextslide = table.unpack(nextvalues)

    if nextslide == 0 then
      send_gate_off()
    end
  end
end

function gridredraw()
  g:all(0)

  -- start/end
  for i, n in ipairs(context.loop.data) do
    g:led(n, 1, 4)
  end

  -- playing pos
  g:led(context.currstep, 1, 5)

  -- editing pos
  g:led(context.cursor, 1, 8)

  -- gate/accent
  for n = 1, 16 do
    local v = 2
    if context.accent[n] == 1 then
      v = 12
    elseif context.gate[n] == 1 then
      v = 5
    else
      v = 0
    end
    g:led(n, 2, v)
  end

  -- slide
  for n = 1, 16 do
    if context.slide[n] == 1 then g:led(n, 3, 5) end
  end

  -- up
  for n = 1, 16 do
    g:led(n, 4, context.octave[n] == 1 and 5 or 0)
  end

  -- down
  for n = 1, 16 do
    g:led(n, 5, context.octave[n] == -1 and 5 or 0)
  end

  local selection = context.note[context.cursor]

  -- keys
  local r = 8
  g:led(1, r, selection == 0 and 5 or 3)
   g:led(2, r-1, selection == 1 and 5 or 3)
  g:led(2, r, selection == 2 and 5 or 3)
   g:led(3, r-1, selection == 3 and 5 or 3)
  g:led(3, r, selection == 4 and 5 or 3)
  g:led(4, r, selection == 5 and 5 or 3)
    g:led(5, r-1, selection == 6 and 5 or 3)
  g:led(5, r, selection == 7 and 5 or 3)
    g:led(6, r-1, selection == 8 and 5 or 3)
  g:led(6, r, selection == 9 and 5 or 3)
   g:led(7, r-1, selection == 10 and 5 or 3)
  g:led(7, r, selection == 11 and 5 or 3)
  g:led(8, r, selection == 12 and 5 or 3)

  -- step left/right
  g:led(15, 6, 5)
  g:led(16, 6, 5)

  -- meta
  g:led(16, r, 5)

  g:refresh()
end

function key(n,z)
  if n == 2 and z == 1 then
    send_transport_rewind_and_start()
  end
  if n == 3 and z == 1 then
    if context.running then
      send_transport_pause()
    else
      send_transport_continue()
    end
    redraw()
  end
end

function g.key(x, y, z)
  -- meta key
  if x == 16 and y == 8 then
    if z == 1 then
      context.meta = true
    else
      context.meta = false
    end
  end

  -- playhead selection (cursor, loop start/end)
  if y == 1 then
    if context.loop_start == nil then
      if z == 1 then
        context.loop_start = x
      end
    else
      if z == 0 then
        if x ~= context.loop_start then
          -- set loop start/end
          context.loop_pending = {}
          local i = 1
          local a
          local b
          if context.loop_start < x then a = context.loop_start else a = x end
          if x > context.loop_start then b = x else b = context.loop_start end
          for n = a,b do
            context.loop_pending[i] = n
            i = i + 1
          end
          context.loop_start = nil
        else
          -- jump immediately to playhead position
          context.cursor = x
          context.loop_start = nil
        end
      end
    end
  end

  -- toggle gate/accent
  if y == 2 and z == 1 then
    -- if meta key is down
    if context.meta then
      -- clear immediately
      context.accent[x] = 0
      context.gate[x] = 0

    else
      if context.accent[x] == 1 then
        context.accent[x] = 0
        context.gate[x] = 0
      elseif context.gate[x] == 1 then
        context.accent[x] = 1
        context.gate[x] = 1
      else 
        context.gate[x] = 1
      end
    end

    -- update the cursor loc
    context.cursor = x
  end

  -- slide
  if y == 3 and z == 1 then
    if context.slide[x] == 1 then
      context.slide[x] = 0
    else
      context.slide[x] = 1
    end

    -- update the cursor loc
    context.cursor = x
  end

  -- up
  if y == 4 and z == 1 then
    if context.octave[x] == 1 then
      context.octave[x] = 0
    else
      context.octave[x] = 1
    end

    -- update the cursor loc
    context.cursor = x
  end
  -- down
  if y == 5 and z == 1 then
    if context.octave[x] == -1 then
      context.octave[x] = 0
    else
      context.octave[x] = -1
    end

    -- update the cursor loc
    context.cursor = x
  end

  -- left
  if y == 6 and x == 15 and z == 1 then
    context.cursor = context.cursor - 1
    if context.cursor < 1 then context.cursor = context.length end
  end

  -- right
  if y == 6 and x == 16 and z == 1 then
    context.cursor = context.cursor + 1
    if context.cursor > context.length then context.cursor = 1 end
  end

  -- note input
  if z == 1 then
    if x == 1 and y == 8 then context.note[context.cursor] = 0 end
    if x == 2 and y == 7 then context.note[context.cursor] = 1 end
    if x == 2 and y == 8 then context.note[context.cursor] = 2 end
    if x == 3 and y == 7 then context.note[context.cursor] = 3 end
    if x == 3 and y == 8 then context.note[context.cursor] = 4 end
    if x == 4 and y == 8 then context.note[context.cursor] = 5 end
    if x == 5 and y == 7 then context.note[context.cursor] = 6 end
    if x == 5 and y == 8 then context.note[context.cursor] = 7 end
    if x == 6 and y == 7 then context.note[context.cursor] = 8 end
    if x == 6 and y == 8 then context.note[context.cursor] = 9 end
    if x == 7 and y == 7 then context.note[context.cursor] = 10 end
    if x == 7 and y == 8 then context.note[context.cursor] = 11 end
    if x == 8 and y == 8 then context.note[context.cursor] = 12 end
  end

  context.pattern:settable(get_pattern_table(context))

  gridredraw()
  redraw()
end

function redraw()
  screen.clear()

  screen.aa(1)

  -- screen.move(0, 7)
  -- screen.font_size(10)
  -- screen.font_face(17)
  -- screen.text("ACID")
  -- screen.close()

  screen.aa(1)
  screen.line_width(1)

  screen.level(15)
  screen.move(80, 32)
  screen.circle(64, 32, 16)
  screen.level(15)
  screen.fill()
  screen.close()

  screen.aa(1)
  screen.line_width(1.75)
  screen.level(0)
  screen.arc(64, 32, 10, (math.pi*2) + 0.15, (math.pi*3) - 0.15)
  screen.stroke()
  screen.close()

  screen.move(59, 24)
  screen.line(59, 31)
  screen.stroke()
  screen.close()

  screen.move(69, 24)
  screen.line(69, 31)
  screen.stroke()
  screen.close()

  screen.aa(0)

  screen.move(0, 63)
  if context.running then
    screen.level(15)
    screen.text("RESTART")
  else
    screen.level(6)
    screen.text("START")
  end

  screen.level(6)
  if context.running then
    screen.level(6)
    screen.move(86, 63)
    screen.text("STOP")
    screen.move(105, 63)
    screen.text("/")
    -- screen.level(15)
    screen.move(111, 63)
    screen.text("CONT")
  else
    screen.level(15)
    screen.move(86, 63)
    screen.text("STOP")
    screen.move(105, 63)
    screen.text("/")
    -- screen.level(6)
    screen.move(111, 63)
    screen.text("CONT")
  end

  if norns.crow.connected() then
    screen.level(15)
  else
    screen.level(2)
  end
  screen.move(121, 5)
  screen.text("^^")

  screen.update()
end

function init()
  params:add_separator("PATTERNS")

  params:add_trigger("acid_load", "> LOAD" )
  params:set_action("acid_load", pattern_load)

  params:add_trigger("acid_save", "> SAVE")
  params:set_action("acid_save", pattern_save)

  params:add_trigger("acid_overwrite", "> OVERWRITE")
  params:set_action("acid_overwrite", pattern_overwrite)

  params:add_trigger("acid_remove", "< REMOVE")
  params:set_action("acid_remove", pattern_remove)



  context.pattern:settable(get_pattern_table(context))

  clock.run(
  function()
    while true do
      clock.sync(1/24)
      on_pulse()
      gridredraw()
      redraw()
    end
  end
  )
end