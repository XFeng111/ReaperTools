--[[
  功能：从TXT文件读取名称创建连续的regions
  特点：每个region使用指定时长，间隔5秒，从当前光标位置开始
]]

-- 选择要读取的TXT文件
local retval,file_path = reaper.GetUserFileNameForRead("", "选择包含region名称的TXT文件", "txt")
if not file_path then return end

-- 让用户输入每个region的时长（秒）
local retval, user_input = reaper.GetUserInputs("Region时长", 1, "每个Region的时长(秒):", "5")
if not retval then return end
local region_duration = tonumber(user_input)
if not region_duration or region_duration <= 0 then
  reaper.ShowMessageBox("请输入有效的时长数值", "错误", 0)
  return
end

-- 读取TXT文件内容
local file = io.open(file_path, "r")
if not file then
  reaper.ShowMessageBox("无法打开文件", "错误", 0)
  return
end

local region_names = {}
for line in file:lines() do
  -- 忽略空行
  if line:gsub("%s+", "") ~= "" then
    table.insert(region_names, line)
  end
end
file:close()

if #region_names == 0 then
  reaper.ShowMessageBox("文件中没有有效的region名称", "提示", 0)
  return
end

-- 根据时长确定region颜色（使用REAPER的颜色代码）
local function get_region_color(duration)
  -- 例如：黄色 (RGB: 255, 255, 0)，自定义修改
    if duration == 5 then
    local color = reaper.ColorToNative(255, 128, 128) -- 转换RGB为REAPER原生颜色
    color = color | 0x1000000 -- 添加自定义颜色标记
    return color  
  -- 例如：蓝色 (RGB: 0, 0, 255)，自定义修改
  elseif duration >= 30 and duration <= 60 then
    local color = reaper.ColorToNative(60, 150, 255) -- 转换RGB为REAPER原生颜色
    color = color | 0x1000000 -- 添加自定义颜色标记
    return color  
  -- 默认颜色
  else
    return 0  -- 0表示使用默认颜色
  end
end

-- 获取当前region颜色
local region_color = get_region_color(region_duration)

-- 开始创建regions
reaper.Undo_BeginBlock()

-- 获取当前光标位置作为起始点
local current_pos = reaper.GetCursorPosition()
local start_pos = current_pos

-- 逐个创建region
for i, name in ipairs(region_names) do
    local end_pos = start_pos + region_duration

    -- 创建region（最后一个参数为true表示是region而不是marker）
    reaper.AddProjectMarker2(0, true, start_pos, end_pos, name, i, region_color)

    -- 计算下一个region的开始位置（当前结束位置 + 5秒间隔）
    start_pos = end_pos + 5
end

reaper.Undo_EndBlock("从TXT创建连续regions", -1)
reaper.UpdateArrange()

local color_info = ""
if region_duration == 5 then
  color_info = "，颜色已设置为黄色"
elseif region_duration >=30 and region_duration <=60 then
  color_info = "，颜色已设置为蓝色"
end

reaper.ShowMessageBox(string.format("成功创建了 %d 个regions", #region_names, color_info), "完成", 0)
