-- 开始撤销块
reaper.Undo_BeginBlock()

-- 获取当前选中的时间选区
local start_time, end_time = reaper.GetSet_LoopTimeRange(0, 0, 0, 0, 0)

-- 检查是否有时间选区
if start_time == end_time then
    reaper.ShowMessageBox("未选中时间选区，请先选中时间选区。", "提示", 0)
    -- 结束撤销块（若未执行有效操作，撤销块为空）
    reaper.Undo_EndBlock("No valid time selection", -1)
    return
end

-- 获取所有区域
local num_markers, num_regions = reaper.CountProjectMarkers(0)

-- 标记时间选区下是否有 region
local has_region = false
-- 标记是否所有区域都有尾缀
local all_have_suffix = true

-- 遍历所有区域
for i = 0, num_markers + num_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers3(0, i)
    if isrgn and pos >= start_time and rgnend <= end_time then
        has_region = true
        -- 检查名称是否有尾缀
        if not string.match(name, "%.[%w]+$") then
            all_have_suffix = false
            break
        end
    end
end

-- 检查时间选区下是否有 region
if not has_region then
    reaper.ShowMessageBox("时间选区下无 region，请选择包含 region 的时间选区。", "提示", 0)
    -- 结束撤销块（若未找到有效区域，撤销块为空）
    reaper.Undo_EndBlock("No valid regions in time selection", -1)
    return
end

-- 检查是否所有区域都有尾缀
if not all_have_suffix then
    reaper.ShowMessageBox("时间选区下存在无尾缀的区域。", "提示", 0)
    reaper.Undo_EndBlock("Some regions have no suffix", -1)
    return
end

-- 再次遍历所有区域进行操作
for i = 0, num_markers + num_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber = reaper.EnumProjectMarkers3(0, i)
    if isrgn and pos >= start_time and rgnend <= end_time then
        -- 查找并删除名称中的文件扩展名
        local new_name = name:gsub("%.[%w]+$", "")

        -- 将光标移动到区域起始位置
        reaper.SetEditCurPos(pos, 1, 0)

        -- 运行指令 ID 为 40615
        reaper.Main_OnCommand(40615, 0)

        -- 使用 reaper.AddProjectMarker2 更新区域名称
        reaper.AddProjectMarker2(0, 1, pos, rgnend, new_name, markrgnindexnumber, -1)
    end
end

-- 删除时间选区
reaper.GetSet_LoopTimeRange(1, 0, 0, 0, 0)

-- 更新项目视图
reaper.UpdateArrange()

-- 结束撤销块，指定撤销操作的描述
reaper.Undo_EndBlock("Process regions in time selection", -1)
