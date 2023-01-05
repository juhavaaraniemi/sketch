-- sketch
-- v 0.5
--
-- isomorphic keyboard 
-- and pattern recorder 
-- for sketching
--
-- speaks molly the poly
--
-- e1   scale
-- e2   root note
-- e3   transpose grid


--
-- LIBRARIES
--
pattern_time = require 'pattern_time'
musicutil = require 'musicutil'
MollyThePoly = require "molly_the_poly/lib/molly_the_poly_engine"
engine.name = "MollyThePoly"


--
-- DEVICES
--
g = grid.connect()
m = midi.connect()


--
-- VARIABLES
--
PATH = _path.data.."sketch/"
grid_dirty = true
screen_dirty = true
scale_names = {}
for i = 1, #musicutil.SCALES do
  table.insert(scale_names, musicutil.SCALES[i].name)
end
lit = {}
pat_timer = {}
undo_timer = {}
blink_counter = 0
blink = false


--
-- INIT FUNCTIONS
--
function init_parameters()
  params:add_separator("SKETCH")
  params:add_group("SKETCH - ROUTING",2)
  params:add{
    type="option",
    id="output",
    name="output",
    options={"audio","midi","audio+midi"},
    default=1
  }
  params:add{
    type="number",
    id="note_channel",
    name="midi note channel",
    min=1,
    max=16,
    default=1
  }
  params:add_group("SKETCH - KEYBOARD",4)
  params:add{
    type="option",
    id="scale",
    name="scale",
    options=scale_names,
    default=41,
    action=function()
      build_scale()
    end
  }
  params:add{
    type="number",
    id="root_note",
    name="root note",
    min=0,
    max=11,
    default=0,
    formatter=function(param)
      return musicutil.note_num_to_name(param:get(),false)
    end
  }
  params:add{
    type="number",
    id="ytranspose",
    name="transpose y",
    min=0,
    max=13,
    default=5
  }
  params:add{
    type="number",
    id="row_interval",
    name="row interval",
    min=1,
    max=12,
    default=5
  }
  params:bang()
end

function init_molly()
  params:add_group("SKETCH - MOLLY THE POLY",46)
  MollyThePoly.add_params()
end

function init_pattern_recorders()
  grid_pattern = {}
  for i=1,8 do
    grid_pattern[i] = pattern_time.new()
    grid_pattern[i].process = grid_note
  end
  active_grid_pattern = 1
end

function init()
  init_parameters()
  init_molly()
  init_pattern_recorders()
  init_pset_callbacks()
  clock.run(grid_redraw_clock)
  clock.run(redraw_clock)
end


--
-- CALLBACK FUNCTIONS
--
function init_pset_callbacks()
  params.action_write = function(filename,name,number)
    local pattern_data = {}
    for i=1,8 do
      local pattern_file = PATH.."sketch-"..number.."_pattern_"..i..".pdata"
      if grid_pattern[i].count > 0 then
        pattern_data[i] = {}
        pattern_data[i].event = grid_pattern[i].event
        pattern_data[i].time = grid_pattern[i].time
        pattern_data[i].count = grid_pattern[i].count
        pattern_data[i].time_factor = grid_pattern[i].time_factor
        tab.save(pattern_data[i],pattern_file)
      else
        if util.file_exists(pattern_file) then
          os.execute("rm "..pattern_file)
        end    
      end
    end
    print("finished writing '"..filename.."' as '"..name.."' and PSET number: "..number)
  end
  
  params.action_read = function(filename,silent,number)
    local pset_file = io.open(filename, "r")
    local pattern_data = {}
    for i=1,8 do
      local pattern_file = PATH.."sketch-"..number.."_pattern_"..i..".pdata"
      if util.file_exists(pattern_file) then
        pattern_data[i] = {}
        grid_pattern[i]:rec_stop()
        grid_pattern[i]:stop()
        grid_pattern[i]:clear()
        pattern_data[i] = tab.load(pattern_file)
        for k,v in pairs(pattern_data[i]) do
          grid_pattern[i][k] = v
        end
      end
    end
    grid_dirty = true
    screen_dirty = true
    print("finished reading '"..filename.."' as PSET number: "..number)
  end
  
  params.action_delete = function(filename,name,number)
    print("finished deleting '"..filename.."' as '"..name.."' and PSET number: "..number)
    for i=1,8 do
      local pattern_file = PATH.."sketch-"..number.."_pattern_"..i..".pdata"
      print(pattern_file)
      if util.file_exists(pattern_file) then
        os.execute("rm "..pattern_file)
      end
    end
  print("finished deleting '"..filename.."' as '"..name.."' and PSET number: "..number)
  end
end


--
-- CLOCK FUNCTIONS
--
function grid_redraw_clock()
  while true do
    clock.sleep(1/30)
--    if grid_dirty then
      grid_redraw()
--      grid_dirty = false
--    end
    
    if blink_counter == 5 then
      blink = not blink
      blink_counter = 0
    else
      blink_counter = blink_counter + 1
    end
  end
end

function redraw_clock()
  while true do
    clock.sleep(1/30)
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
  end
end


--
-- NOTE FUNCTIONS
--
function note_on(id,note_num)
  if params:get("output") == 1 then
    engine.noteOn(id,musicutil.note_num_to_freq(note_num),80)
  elseif params:get("output") == 2 then
    m:note_on(id,note_num, vel)
  elseif params:get("output") == 3 then
    m:note_on(note_num, vel)
    engine.noteOn(id,musicutil.note_num_to_freq(note_num),80)
  end
end

function note_off(id,note_num)
  if params:get("output") == 1 then
    engine.noteOff(id)
  elseif params:get("output") == 2 then
    m:note_off(note_num)
  elseif params:get("output") == 3 then
    m:note_off(note_num)
    engine.noteOff(id)
  end
end

function clear_pattern_notes(pattern)
  for i,e in pairs(grid_pattern[pattern].event) do
    if e.state == 1 then
      local n = {}
      n.id = e.id
      n.note = e.note
      n.state = 0
      grid_note(n)
    end
  end
end

function grid_note(e)
  if e.state == 1 then
    note_on(e.id,e.note+params:get("root_note"))
    print(e.note+params:get("root_note"))
    lit[e.id] = {}
    lit[e.id].pattern = e.pattern
    lit[e.id].x = e.x --+e.trans-params:get("xtranspose")
    lit[e.id].y = e.y-e.trans+params:get("ytranspose")
  elseif e.state == 0 then
    if lit[e.id] ~= nil then
      note_off(e.id,e.note+params:get("root_note"))
      lit[e.id] = nil
    end
  end
  grid_redraw()
end

function get_note(x,y)
  return util.clamp((8-y)*params:get("row_interval")+params:get("ytranspose")*params:get("row_interval")+(x-3),0,120)
end

function note_in_scale(note)
  return in_scale[note] ~= nil
end


function build_scale()
  note_nums = {}
  if params:get("scale") < 41 then
    note_nums = musicutil.generate_scale_of_length(0,params:get("scale"),120)
  end
  in_scale = {}
  for _,v in pairs(note_nums) do
    in_scale[v] = true
  end
  grid_dirty = true
end


--
-- UI FUNCTIONS
--
function key(n,z)
end

function enc(n,d)
  if n == 1 then
    params:delta("scale",d)
  elseif n == 2 then
    params:delta("root_note",d)
  elseif n == 3 then
    params:delta("ytranspose",d)
  end
  screen_dirty = true
end

function g.key(x,y,z)
  -- pattern recorders
  if x == 1 then
     if not (grid_pattern[active_grid_pattern].rec == 1 or grid_pattern[active_grid_pattern].overdub == 1) then
      active_grid_pattern = y
    end
    if z == 1 then
      if y ~= active_grid_pattern then
        pattern_stop_press(active_grid_pattern)
        active_grid_pattern = y
      end
      pattern_rec_press(active_grid_pattern)
    end
  elseif x == 2 then
    if not (grid_pattern[active_grid_pattern].rec == 1 or grid_pattern[active_grid_pattern].overdub == 1) then
      active_grid_pattern = y
    end
    if z == 1 then
      pat_timer[active_grid_pattern] = clock.run(pattern_clear_press,active_grid_pattern)
    elseif z == 0 then
      if pat_timer[active_grid_pattern] then
        clock.cancel(pat_timer[active_grid_pattern])
        pattern_stop_press(active_grid_pattern)
      end
    end

  -- notes
  elseif x > 2 then
    local e = {}
    e.id = get_note(x,y)..x..y
    --print(e.id)
    e.pattern = active_grid_pattern
    e.note = get_note(x,y)
    e.trans = params:get("ytranspose")
    e.x = x
    e.y = y
    e.state = z
    grid_pattern[active_grid_pattern]:watch(e)
    grid_note(e)
  end
  grid_dirty = true
end

function pattern_clear_press(pattern)
  clock.sleep(0.5)
  grid_pattern[pattern]:stop()
  clear_pattern_notes(pattern)
  grid_pattern[pattern]:clear()
  pat_timer[pattern] = nil
  grid_dirty = true
  screen_dirty = true
end

function pattern_stop_press(pattern)
  grid_pattern[pattern]:rec_stop()
  grid_pattern[pattern]:stop()
  clear_pattern_notes(pattern)
  grid_dirty = true
  screen_dirty = true
end

function pattern_rec_press(pattern)
  if grid_pattern[pattern].rec == 0 and grid_pattern[pattern].count == 0 then
    grid_pattern[pattern]:stop()
    grid_pattern[pattern]:rec_start()
  elseif grid_pattern[pattern].rec == 1 then
    grid_pattern[pattern]:rec_stop()
    clear_pattern_notes(pattern)
    grid_pattern[pattern]:start()
  elseif grid_pattern[pattern].play == 1 and grid_pattern[pattern].overdub == 0 then
    grid_pattern[pattern]:set_overdub(1)
  elseif grid_pattern[pattern].play == 1 and grid_pattern[pattern].overdub == 1 then
    grid_pattern[pattern]:set_overdub(0)
  elseif grid_pattern[pattern].play == 0 and grid_pattern[pattern].count > 0 then
    --for i=1,8 do
    --  if i ~= pattern then
    --    grid_pattern[i]:stop()
    --  end
    --end
    grid_pattern[pattern]:start()
  end
  grid_dirty = true
  screen_dirty = true
end

--
-- REDRAW FUNCTIONS
--

function redraw()
  screen.clear()
  screen.level(15)
  screen.move(0,39)
  screen.text("output: "..params:string("output"))
  screen.move(0,46)
  screen.text("transpose y: "..params:get("ytranspose"))
  screen.move(0,53)
  screen.text("root note: "..musicutil.note_num_to_name(params:get("root_note"), false))
  screen.move(0,60)
  screen.text("scale: "..scale_names[params:get("scale")])
  screen.update()
end

function grid_redraw()
  g:all(0)
  for y= 1,8 do
    for x= 1,2 do
      if x == 1 then
        if grid_pattern[y].play == 1 and grid_pattern[y].overdub == 1 and blink then
          g:led(x,y,15)
        elseif grid_pattern[y].play == 1 and grid_pattern[y].overdub == 0 then
          g:led(x,y,15)
        elseif grid_pattern[y].rec == 1 and blink then
          g:led(x,y,15)
        else
          g:led(x,y,2)
        end
      elseif x == 2 then
        if grid_pattern[y].count > 0 then
          g:led(x,y,15)
        else
          g:led(x,y,2)
        end
      end
    end
  end

  for x = 3,16 do
    for y = 8,1,-1 do
      -- scale notes
      if note_in_scale(get_note(x,y)) then
        g:led(x,y,4)
      end
      -- root notes
      if (get_note(x,y)) % 12 == 0 then
        g:led(x,y,8)
      end
    end
  end
  
  -- lit when pressed
  for i,e in pairs(lit) do
    if e.x > 2 and e.x < 17 then
      if e.y > 0 and e.y < 9 then
        g:led(e.x, e.y,15)
      end
    end
  end
  g:refresh()
end
