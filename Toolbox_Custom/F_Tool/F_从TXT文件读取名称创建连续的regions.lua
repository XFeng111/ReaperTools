--[[
  功能：从TXT文件读取带标记的名称创建连续的regions
  特点：通过"--数字--"标记区分不同时长，相同时长颜色一致，不同时长颜色区分
        无标记则提示输入时长
        每个region间隔5秒，从当前光标位置开始
例如：
  --5--
  region1
  region2

  --10--
  region3
  region4

  --30--
  region5
运行结果：
region1：颜色A，5s
region2：颜色A，5s

region3：颜色B，10s
region4：颜色B，10s

region5：颜色C，30s
]]

-- 选择要读取的TXT文件
local retval, file_path = reaper.GetUserFileNameForRead("", "选择包含region名称的TXT文件", "txt")
if not file_path then return end

-- 读取TXT文件内容并解析区块
local file = io.open(file_path, "r")
if not file then
  reaper.ShowMessageBox("无法打开文件", "错误", 0)
  return
end

local regions_data = {}  -- 存储解析后的区块数据: { {duration, names = {}}, ... }
local current_duration = nil
local current_names = {}

-- 解析文件内容，按"--数字--"分割区块
for line in file:lines() do
  -- 去除首尾空白
  local trimmed_line = line:gsub("^%s+", ""):gsub("%s+$", "")
  
  -- 忽略空行
  if trimmed_line ~= "" then
    -- 检查是否是时长标记行 (格式: --数字--)
    local duration = trimmed_line:match("^%-%-(%d+)%-%-$")
    if duration then
      -- 如果是新的标记，保存上一个区块(如果存在)
      if current_duration then
        table.insert(regions_data, {
          duration = tonumber(current_duration),
          names = current_names
        })
      end
      -- 开始新的区块
      current_duration = duration
      current_names = {}
    else
      -- 不是标记行，作为名称添加到当前区块
      table.insert(current_names, trimmed_line)
    end
  end
end

-- 添加最后一个区块
if current_duration and #current_names > 0 then
  table.insert(regions_data, {
    duration = tonumber(current_duration),
    names = current_names
  })
end

file:close()

-- 处理没有找到任何标记的情况
if #regions_data == 0 then
  local retval, user_input = reaper.GetUserInputs("默认时长", 1, "未找到时长标记，请输入默认时长(秒):", "5")
  if not retval then return end
  local default_duration = tonumber(user_input)
  if not default_duration or default_duration <= 0 then
    reaper.ShowMessageBox("请输入有效的时长数值", "错误", 0)
    return
  end
  
  -- 重新读取文件内容作为默认区块的名称
  local file = io.open(file_path, "r")
  if file then
    current_names = {}
    for line in file:lines() do
      local trimmed_line = line:gsub("^%s+", ""):gsub("%s+$", "")
      if trimmed_line ~= "" then
        table.insert(current_names, trimmed_line)
      end
    end
    file:close()
  end
  
  if #current_names == 0 then
    reaper.ShowMessageBox("文件中没有有效的region名称", "提示", 0)
    return
  end
  
  table.insert(regions_data, {
    duration = default_duration,
    names = current_names
  })
end

-- 为不同时长生成独特颜色（相同时长颜色一致）
local color_map = {}  -- 存储时长到颜色的映射
local hue_offset = 0  -- 色相偏移量，用于生成不同颜色

local function get_region_color(duration)
  -- 如果该时长已有颜色，直接返回
  if color_map[duration] then
    return color_map[duration]
  end
  
  -- 生成新的颜色（使用HSV颜色空间，保持饱和度和明度一致，只改变色相）
  local hue = (hue_offset % 360) / 360  -- 色相 0-1
  local saturation = 0.7  -- 饱和度
  local value = 0.8      -- 明度
  
  -- HSV转RGB
  local r, g, b
  local i = math.floor(hue * 6)
  local f = hue * 6 - i
  local p = value * (1 - saturation)
  local q = value * (1 - f * saturation)
  local t = value * (1 - (1 - f) * saturation)
  
  i = i % 6
  if i == 0 then r, g, b = value, t, p
  elseif i == 1 then r, g, b = q, value, p
  elseif i == 2 then r, g, b = p, value, t
  elseif i == 3 then r, g, b = p, q, value
  elseif i == 4 then r, g, b = t, p, value
  else r, g, b = value, p, q end
  
  -- 转换为0-255范围
  r = math.floor(r * 255)
  g = math.floor(g * 255)
  b = math.floor(b * 255)
  
  -- 转换为REAPER原生颜色格式
  local color = reaper.ColorToNative(r, g, b)
  color = color | 0x1000000  -- 添加自定义颜色标记
  
  -- 存储颜色映射并更新偏移量
  color_map[duration] = color
  hue_offset = hue_offset + 60  -- 每次增加60度色相，确保颜色差异明显
  
  return color
end

-- 开始创建regions
reaper.Undo_BeginBlock()

-- 获取当前光标位置作为起始点
local current_pos = reaper.GetCursorPosition()
local start_pos = current_pos
local total_count = 0 -- 统计总创建数量
local duration_counts = {}  -- 记录每种时长的数量

-- 逐个区块创建region
for _, block in ipairs(regions_data) do
  local duration = block.duration
  local color = get_region_color(duration)
  local count = #block.names
  
  -- 记录该时长的数量
  duration_counts[duration] = count
  
  -- 为当前区块的每个名称创建region
  for i, name in ipairs(block.names) do
    local end_pos = start_pos + duration
    
    -- 创建region（最后一个参数为true表示是region而不是marker）
    reaper.AddProjectMarker2(0, true, start_pos, end_pos, name, total_count + i, color)
    
    -- 计算下一个region的开始位置（当前结束位置 + 5秒间隔）
    start_pos = end_pos + 5
  end
  
  total_count = total_count + count
end

reaper.Undo_EndBlock("从TXT创建带不同时长的regions", -1)
reaper.UpdateArrange()

-- 显示创建结果
local message = "总计： " .. total_count .. " 个regions\n".."————————————\n\n"
for duration, count in pairs(duration_counts) do
    message = message .. "创建： " .. count .. " 个region，" .. duration .. "s\n"
end

reaper.ShowMessageBox(message, "完成", 0)
