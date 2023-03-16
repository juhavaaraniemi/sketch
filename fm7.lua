-- sketch
-- v 0.9
--
-- isomorphic keyboard 
-- and pattern recorder 
-- for sketching
--
-- listens to grid
-- speaks fm7
-- reads and writes midi
--
-- e1   scale
-- e2   root note
-- e3   transpose grid
-- k2   audio on/off
-- k3   midi send/receive/off


--
-- LIBRARIES
--
pattern_time = require 'pattern_time'
musicutil = require 'musicutil'
package.loaded["mftconf/lib/mftconf"] = nil
mftconf = require "mftconf/lib/mftconf"
FM7 = require "fm7/lib/fm7"
engine.name = "FM7"


--
-- DEVICES
--
g = grid.connect()


--
-- VARIABLES
--
PATH = _path.data.."sketch/fm7/"
grid_dirty = true
screen_dirty = true
scale_names = {}
for i = 1, #musicutil.SCALES do
  table.insert(scale_names, string.lower(musicutil.SCALES[i].name))
end
lit = {}
pat_timer = {}
undo_timer = {}
blink_counter = 0
blink = false
shifted = false
arrangement = {}
arrangement_play = false


--
-- INIT FUNCTIONS
--
function init_parameters()
  params:add_separator("SKETCH")
  params:add_group("SKETCH - ROUTING",7)
  params:add{
    type="option",
    id="audio",
    name="audio output",
    options={"on","off"},
    default=1,
    action = function(value)
      note_off_all()
    end
  }
  params:add{
    type="option",
    id="midi",
    name="midi",
    options={"send","receive","off"},
    default=1,
    action = function(value)
      note_off_all()
    end
  }
  params:add{
    type = "number",
    id = "midi_in_device",
    name = "midi in device",
    min = 1,
    max = 4,
    default = 1,
    action = function(value)
      note_off_all()
      midi_in_device.event = nil
      midi_in_device = midi.connect(value)
      midi_in_device.event = midi_event
    end
  }
  params:add{
    type="number",
    id="midi_in_channel",
    name="midi in channel",
    min=1,
    max=16,
    default=1
  }
  params:add{
    type = "number",
    id = "midi_out_device",
    name = "midi out device",
    min = 1,
    max = 4,
    default = 1,
    action = function(value)
      note_off_all()
      midi_out_device = midi.connect(value)
    end
  }
  params:add{
    type="number",
    id="midi_out_channel",
    name="midi out channel",
    min=1,
    max=16,
    default=1
  }
    params:add{
    type = "number",
    id = "midi_ctrl_device",
    name = "midi ctrl device",
    min = 1,
    max = 4,
    default = 2,
    action = function(value)
      midi_ctrl_device = midi.connect(value)
    end
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
    end,
    action=function()
      clear_ringing_notes()
    end
  }
  params:add{
    type="number",
    id="ytranspose",
    name="transpose y",
    min=0,
    max=13,
    default=5,
    action=function()
      clear_ringing_notes()
    end
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

function init_fm7()
  params:add_group("SKETCH - FM7",89)
  FM7.add_params()
  engine.amp(0.05)
end

function init_pattern_recorders()
  grid_pattern = {}
  pattern_backup = {}
  for i=1,8 do
    grid_pattern[i] = pattern_time.new()
    grid_pattern[i].process = grid_note
    pattern_backup[i] = {}
  end
  active_grid_pattern = 1
end

function init_midi_devices()
  midi_in_device = midi.connect(1)
  midi_in_device.event = midi_event
  midi_out_device = midi.connect(1)
  midi_ctrl_device = midi.connect(2)
end

function init_poll_params()
  last_param_id = ""
  last_param_name = ""
  last_param_value = ""
  param_values = {}
  for i=1,params.count do
    param_id = params:get_id(i)
    param_values[params:get_id(i)] = params:get(params:get_id(i))
  end
end

function init()
  init_midi_devices()
  init_parameters()
  init_fm7()
  init_pattern_recorders()
  init_pset_callbacks()
  init_poll_params()
  mftconf.load_conf(midi_ctrl_device,PATH.."mft_fm7.mfs")
  mftconf.refresh_values(midi_ctrl_device)
  grid_redraw_metro = metro.init(grid_redraw_event, 1/30, -1)
  grid_redraw_metro:start()
  redraw_metro = metro.init(redraw_event, 1/30, -1)
  redraw_metro:start()
  poll_params_metro = metro.init(poll_params_event, 1/30, -1)
  poll_params_metro:start()
  arrangement_metro = metro.init(function() play_next_pattern() end,1,1)
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
    local arrangement_file = PATH.."sketch-"..number.."_arrangement.adata"
    if #arrangement > 0 then
      tab.save(arrangement,arrangement_file)
    else
      if util.file_exists(arrangement_file) then
          os.execute("rm "..arrangement_file)
      end
    end
    print("finished writing '"..filename.."' as '"..name.."' and PSET number: "..number)
  end

  params.action_read = function(filename,silent,number)
    local pset_file = io.open(filename, "r")
    local pattern_data = {}
    for i=1,8 do
      grid_pattern[i]:rec_stop()
      grid_pattern[i]:stop()
      grid_pattern[i]:clear()
      local pattern_file = PATH.."sketch-"..number.."_pattern_"..i..".pdata"
      if util.file_exists(pattern_file) then
        pattern_data[i] = {}
        pattern_data[i] = tab.load(pattern_file)
        for k,v in pairs(pattern_data[i]) do
          grid_pattern[i][k] = v
        end
      end
    end
    local arrangement_file = PATH.."sketch-"..number.."_arrangement.adata"
    arrangement = {}
    if util.file_exists(arrangement_file) then
      arrangement = tab.load(arrangement_file)
    end
    mftconf.refresh_values(midi_ctrl_device)
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
    local arrangement_file = PATH.."sketch-"..number.."_arrangement.adata"
    if util.file_exists(arrangement_file) then
      os.execute("rm "..arrangement_file)
    end
    print("finished deleting '"..filename.."' as '"..name.."' and PSET number: "..number)
  end
end


--
-- CLOCK FUNCTIONS
--
function grid_redraw_event()
  if blink_counter == 5 then
    blink = not blink
    blink_counter = 0
    grid_dirty = true
  else
    blink_counter = blink_counter + 1
  end

  if grid_dirty then
    grid_redraw()
    grid_dirty = false
  end
end

function redraw_event()
  if screen_dirty then
    redraw()
    screen_dirty = false
  end
end

function poll_params_event()
  for i=1,params.count do
    param_id = params:get_id(i)
    if param_values[param_id] ~= params:get(param_id) then
      params:get_id(i)
      last_param_id = param_id
      last_param_name = params:lookup_param(i).name
      last_param_value = params:string(params:get_id(i))
      param_values[params:get_id(i)] = params:get(params:get_id(i))
      mftconf.mft_redraw(midi_ctrl_device,last_param_id)
      screen_dirty = true
    end
  end
end


--
-- NOTE FUNCTIONS
--
function note_on(id,note_num)
  if params:get("audio") == 1 then
    engine.start(id,musicutil.note_num_to_freq(note_num))
  end
  if params:get("midi") == 1 then
    midi_out_device:note_on(note_num, 100, params:get("midi_out_channel"))
  end
end

function note_off(id,note_num)
  if params:get("audio") == 1 then
    engine.stop(id)
  end
  if params:get("midi") == 1 then
    midi_out_device:note_off(note_num, 100, params:get("midi_out_channel"))
  end
end

function note_off_all()
  engine.stopAll()
  for i=0,127 do
    midi_out_device:note_off(i, 100, params:get("midi_out_channel"))
  end
end


function midi_event(data)
  local msg = midi.to_msg(data)

  if params:get("midi") == 2 then
    if msg.ch == params:get("midi_in_channel") then
        if msg.type == "note_off" then
          note_off(msg.note, msg.note)
        elseif msg.type == "note_on" then
          note_on(msg.note, msg.note, msg.vel / 127)
        end
    end
  end
end

function clear_ringing_notes()
  for i,e in pairs(lit) do
    local n = {}
    n.id = i
    n.note = e.note
    n.state = 0
    grid_note(n)
  end
end

function grid_note(e)
  if e.state == 1 then
    note_on(e.id,e.note+params:get("root_note"))
    lit[e.id] = {}
    lit[e.id].note = e.note
    lit[e.id].x = e.x
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
  if n == 1 then
    shifted = z == 1
  elseif n == 2 and z == 1 and shifted then
    arrangement_play_press()
  elseif n == 3 and z == 1 and shifted then
    arrangement_clear_press()
  elseif n == 2 and z == 1 then
    if params:get("audio") == 1 then
      params:set("audio",2)
    else
      params:set("audio",1)
    end
  elseif n == 3 and z == 1 then
    if params:get("midi") == 1 then
      params:set("midi",2)
    elseif params:get("midi") == 2 then
      params:set("midi",3)
    elseif params:get("midi") == 3 then
      params:set("midi",1)
    end
  end
  screen_dirty = true
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
    if z == 1 then
      if y ~= active_grid_pattern then
        pattern_stop_press(active_grid_pattern)
        active_grid_pattern = y
      end
      if shifted then 
        print(y.." pattern added to arrangement")
        table.insert(arrangement,y)
      else
        undo_timer[active_grid_pattern] = clock.run(pattern_undo_press,active_grid_pattern)
      end
    elseif z == 0 then
      if not shifted then
        if undo_timer[active_grid_pattern] then
          clock.cancel(undo_timer[active_grid_pattern])
          pattern_rec_press(active_grid_pattern)
        end
      end
    end
  elseif x == 2 then
    if z == 1 then
      if y ~= active_grid_pattern then
        --pattern_stop_press(active_grid_pattern)
        active_grid_pattern = y
      end
      if shifted then
        print("last pattern removed from arrangement")
        table.remove(arrangement)
      else
        pat_timer[active_grid_pattern] = clock.run(pattern_clear_press,active_grid_pattern)
      end
    elseif z == 0 then
      if not shifted then
        if pat_timer[active_grid_pattern] then
          clock.cancel(pat_timer[active_grid_pattern])
          pattern_stop_press(active_grid_pattern)
        end
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
  screen_dirty = true
  grid_dirty = true
end

function pattern_clear_press(pattern)
  clock.sleep(0.5)
  grid_pattern[pattern]:stop()
  clear_ringing_notes(pattern)
  grid_pattern[pattern]:clear()
  pat_timer[pattern] = nil
  grid_dirty = true
  screen_dirty = true
end

function pattern_stop_press(pattern)
  grid_pattern[pattern]:rec_stop()
  grid_pattern[pattern]:stop()
  clear_ringing_notes()
  grid_dirty = true
  screen_dirty = true
end

function pattern_undo_press(pattern)
  clock.sleep(0.5)
  grid_pattern[pattern]:rec_stop()
  grid_pattern[pattern]:stop()
  clear_ringing_notes(pattern)
  grid_pattern[pattern]:clear()
  grid_pattern[pattern].count = pattern_backup[pattern].count
  grid_pattern[pattern].time_factor = pattern_backup[pattern].time_factor
  grid_pattern[pattern].time = pattern_backup[pattern].time
  grid_pattern[pattern].event = pattern_backup[pattern].event
  undo_timer[pattern] = nil
  grid_dirty = true
  screen_dirty = true
end

function backup_pattern(pattern)
  pattern_backup[pattern] = {}
  pattern_backup[pattern].count = grid_pattern[pattern].count
  pattern_backup[pattern].time_factor = grid_pattern[pattern].time_factor
  pattern_backup[pattern].time = deepcopy(grid_pattern[pattern].time)
  pattern_backup[pattern].event = deepcopy(grid_pattern[pattern].event)
end

function pattern_rec_press(pattern)
  if grid_pattern[pattern].rec == 0 and grid_pattern[pattern].count == 0 then
    grid_pattern[pattern]:stop()
    backup_pattern(pattern)
    grid_pattern[pattern]:rec_start()
  elseif grid_pattern[pattern].rec == 1 then
    grid_pattern[pattern]:rec_stop()
    clear_ringing_notes(pattern)
    grid_pattern[pattern]:start()
  elseif grid_pattern[pattern].play == 1 and grid_pattern[pattern].overdub == 0 then
    backup_pattern(pattern)
    grid_pattern[pattern]:set_overdub(1)
  elseif grid_pattern[pattern].play == 1 and grid_pattern[pattern].overdub == 1 then
    grid_pattern[pattern]:set_overdub(0)
  elseif grid_pattern[pattern].play == 0 and grid_pattern[pattern].count > 0 then
    grid_pattern[pattern]:start()
  end
  grid_dirty = true
  screen_dirty = true
end

function arrangement_play_press()
  if arrangement_play then
    arrangement_play = false
    pattern_stop_press(arrangement[arr_step])
    arrangement_metro:stop()
  else
    if #arrangement > 0 then
      arrangement_play = true
      arr_step = 1
      pattern_rec_press(arrangement[arr_step])
      arrangement_metro.time = get_pattern_length(arrangement[arr_step])
      arrangement_metro:start()
    end
  end
end

function arrangement_clear_press()
  if arrangement_play then
    arrangement_play = false
    pattern_stop_press(arrangement[arr_step])
    arrangement_metro:stop()
  end
  arrangement = {}
end


--
-- HELPER FUNCTIONS
--
function get_pattern_length(pattern)
  local length = 0
  for i,e in ipairs(grid_pattern[pattern].time) do
    length = length + e
  end
  return length
end

function play_next_pattern()
  pattern_stop_press(arrangement[arr_step])
  arr_step = arr_step + 1
  if arr_step <= #arrangement then
    pattern_rec_press(arrangement[arr_step])
    arrangement_metro.time = get_pattern_length(arrangement[arr_step])
    arrangement_metro:start()
  else
    arrangement_play = false
    arr_step = 1
  end
end

function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end


--
-- REDRAW FUNCTIONS
--
function redraw()
  
  if shifted then
    screen.clear()
    screen.level(15)
    screen.move(0,11)
    screen.text("arrangement")
    screen.move(0,20)
    if arrangement_play then screen.text("playing") else screen.text("stopped") end
    local rows = math.ceil(#arrangement / 12)
    local row_height = 7
    local row_start_index = 1
    local row_start_loc = 35
    for i=1,rows do
      screen.move(0,row_start_loc)
      for j=row_start_index,(12*i) do
        local arr = ""
        if j <= #arrangement then
          arr = arr..arrangement[j].." "
        end
        screen.text(arr)
      end
      row_start_index = row_start_index+12
      row_start_loc = 35+(i*row_height)
    end
    screen.update()
  else
    screen.clear()
    screen.level(15)
    screen.move(0,11)
    screen.text("audio: "..params:string("audio"))
    screen.move(0,18)
    screen.text("midi: "..params:string("midi"))
    screen.move(0,28)
    screen.text("last: "..last_param_name)
    screen.move(0,35)
    screen.text("value: "..last_param_value)
    screen.move(0,46)
    screen.text("transpose y: "..params:get("ytranspose"))
    screen.move(0,53)
    screen.text("root note: "..musicutil.note_num_to_name(params:get("root_note"), false))
    screen.move(0,60)
    screen.text("scale: "..scale_names[params:get("scale")])
    screen.update()
  end
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
